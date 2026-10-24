import Foundation
import Observation

struct QuickWorkoutDraft: Codable, Equatable {
    var title = "Quick workout"
    var entries: [WorkoutEntry] = []
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !entries.isEmpty
            && entries.count <= 100 && Set(entries.map(\.id)).count == entries.count
            && Set(entries.flatMap(\.sets).map(\.id)).count == entries.flatMap(\.sets).count
            && entries.allSatisfy { entry in
                !entry.skipped && (0...3600).contains(entry.restSeconds) && !entry.sets.isEmpty && entry.sets.count <= 100
                    && entry.sets.allSatisfy { set in
                        set.isValid && set.status == .pending && set.startedAt == nil && set.startedActiveSeconds == nil
                            && set.actual == nil && set.inputTarget == nil && set.timedActiveSeconds == nil && set.loggedActiveSeconds == nil
                            && (entry.exercise.kind == .duration ? set.seconds > 0 : set.reps > 0)
                    }
            }
    }

    mutating func add(_ exercises: [ExerciseDefinition], current: WorkoutSession?, history: [WorkoutSession]) {
        for exercise in exercises where entries.count < 100 {
            guard !entries.contains(where: { $0.exercise.id == exercise.id }) else { continue }
            let prior = history.filter { !$0.isActive && $0.status != .skipped }.flatMap(\.entries)
                .filter { $0.exercise.id == exercise.id && $0.exercise.kind == exercise.kind }
                .filter { $0.sets.contains { $0.status == .completed && $0.isValid } }
                .max { ($0.sets.compactMap(\.completedAt).max() ?? .distantPast) < ($1.sets.compactMap(\.completedAt).max() ?? .distantPast) }
            let count = min(100, max(1, prior?.sets.filter { $0.status == .completed && $0.isValid && $0.type == .working }.count ?? 3))
            let sets = (0..<count).map { _ in WorkoutSet(seconds: exercise.kind == .duration ? 30 : 0) }
            entries.append(WorkoutRecall.seeded(WorkoutEntry(exercise: exercise, sets: sets), current: current, history: history))
        }
    }
}

@MainActor @Observable final class QuickWorkoutDraftStore {
    static let key = "fitout.quickWorkout.configuration.v1"
    var draft: QuickWorkoutDraft { didSet { persist() } }
    private(set) var error: String?
    @ObservationIgnored private let defaults: UserDefaults?
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.key) {
            do { draft = try JSONDecoder().decode(QuickWorkoutDraft.self, from: data) }
            catch { draft = QuickWorkoutDraft(); self.error = "The saved setup could not be read. Create a new setup to continue." }
        } else { draft = QuickWorkoutDraft() }
    }
    func clear() { draft = QuickWorkoutDraft(); defaults?.removeObject(forKey: Self.key); error = nil }
    private func persist() {
        guard let defaults else { return }
        do { defaults.set(try JSONEncoder().encode(draft), forKey: Self.key); error = nil }
        catch { self.error = "Your setup could not be saved. Keep this screen open and try again." }
    }
}

extension WorkoutStore {
    /// The configured session and its first set begin in one save, after explicit Start.
    @discardableResult func startQuickWorkout(_ draft: QuickWorkoutDraft, unit: WeightUnit, now: Date = .now) -> Bool {
        guard active == nil else { error = "Resume or end the current workout first."; return false }
        guard draft.isValid else { error = "Add an exercise and enter positive reps or time for every set."; return false }
        var session = WorkoutSession(title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), startedAt: now, entries: draft.entries)
        for e in session.entries.indices {
            // Replaying a retained setup after an interruption must never reuse history IDs.
            session.entries[e].id = UUID()
            for index in session.entries[e].sets.indices {
                session.entries[e].sets[index].id = UUID()
                session.entries[e].sets[index].editedInputs = [.load, .reps, .seconds, .distance]
            }
        }
        session.inputMemoryVersion = 1
        WorkoutExecutionEngine.prepare(&session, at: now)
        session.execution?.preferredUnit = unit
        do {
            try WorkoutExecutionEngine.apply(.startSet, to: &session, at: now)
            return save(session, at: now)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func addConfiguredExercises(_ entries: [WorkoutEntry], now: Date = .now) -> Bool {
        guard active != nil, QuickWorkoutDraft(entries: entries).isValid else { error = "Check the sets before adding exercises."; return false }
        guard let current = active, Set(current.entries.map(\.id)).isDisjoint(with: Set(entries.map(\.id))),
              Set(current.entries.flatMap(\.sets).map(\.id)).isDisjoint(with: Set(entries.flatMap(\.sets).map(\.id))) else { return false }
        return update(at: now) { session in
            var configured = entries
            for e in configured.indices {
                for index in configured[e].sets.indices { configured[e].sets[index].editedInputs = [.load, .reps, .seconds, .distance] }
            }
            session.entries.append(contentsOf: configured)
            WorkoutExecutionEngine.prepare(&session, at: now)
        }
    }
    /// Merge editable inputs into the latest session, preserving every timer and record.
    @discardableResult func configureExercise(_ edited: WorkoutEntry, original: WorkoutEntry, now: Date = .now) -> Bool {
        guard let latest = active?.entries.first(where: { $0.id == original.id }), edited.id == original.id,
              edited.exercise == original.exercise, !edited.sets.isEmpty, edited.sets.count <= 100,
              Set(edited.sets.map(\.id)).count == edited.sets.count else { return false }
        guard let active, Set(edited.sets.map(\.id)).isDisjoint(with: Set(active.entries.filter { $0.id != latest.id }.flatMap(\.sets).map(\.id))) else { return false }
        var result = latest
        result.restSeconds = edited.restSeconds
        guard (0...3600).contains(result.restSeconds) else { return false }
        var merged: [WorkoutSet] = []
        for proposed in edited.sets {
            if let base = original.sets.first(where: { $0.id == proposed.id }) {
                guard let current = latest.sets.first(where: { $0.id == proposed.id }) else { return false }
                if base.status != .pending {
                    var recorded = current
                    if recorded.restSeconds == nil { recorded.restSeconds = latest.restSeconds }
                    merged.append(recorded); continue
                }
                guard current.status == .pending else { error = "A set changed while editing. Close and reopen its setup."; return false }
                var value = current
                value = WorkoutRecall.copyInputs(value, from: proposed, kind: latest.exercise.kind)
                value.restSeconds = edited.restSeconds != original.restSeconds && proposed.restSeconds == base.restSeconds ? edited.restSeconds : proposed.restSeconds
                if current.startedAt == nil { value.type = proposed.type }
                guard value.isValid, latest.exercise.kind == .duration ? value.seconds > 0 : value.reps > 0 else { error = "Enter positive reps or time and a valid weight."; return false }
                merged.append(value)
            } else {
                guard QuickWorkoutDraft(entries: [WorkoutEntry(exercise: latest.exercise, sets: [proposed])]).isValid else { return false }
                merged.append(proposed)
            }
        }
        for removed in latest.sets where !edited.sets.contains(where: { $0.id == removed.id }) {
            guard original.sets.contains(where: { $0.id == removed.id }), removed.status == .pending,
                  removed.startedAt == nil, active.execution?.setID != removed.id else {
                error = "The current or a recorded set cannot be removed."; return false
            }
        }
        // Do not silently drop sets appended by another surface while this editor was open.
        guard Set(latest.sets.map(\.id)) == Set(original.sets.map(\.id)) else {
            error = "The set list changed while editing. Close and reopen its setup."; return false
        }
        result.sets = merged
        return update(at: now) { session in
            guard let index = session.entries.firstIndex(where: { $0.id == result.id }) else { return }
            session.entries[index] = result
            WorkoutExecutionEngine.prepare(&session, at: now)
        }
    }
}

/// Shared validation keeps typed decimal/integer input out of the saved model until valid.
enum WorkoutConfigurationValue {
    static func parse(_ text: String, maximum: Double, integer: Bool, positive: Bool, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> Double? {
        guard let number = Double(text.replacingOccurrences(of: decimalSeparator, with: ".")),
              number.isFinite, number >= (positive ? 1 : 0), number <= maximum,
              !integer || number.rounded() == number else { return nil }
        return number
    }
}

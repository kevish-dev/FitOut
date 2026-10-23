import Foundation
import SwiftData
import Observation

@MainActor @Observable final class WorkoutStore {
    private let context: ModelContext
    private(set) var sessions: [WorkoutSession] = []
    var error: String?
    var onChange: (() -> Void)?
    init(container: ModelContainer) throws { context = ModelContext(container); context.autosaveEnabled = false; try reload() }
    var active: WorkoutSession? { sessions.first(where: \.isActive) }
    var history: [WorkoutSession] { sessions.filter { !$0.isActive } }
    func reload() throws {
        let details = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<FitOutSchemaV5.SessionDetails>()).map { ($0.id, $0.payload) })
        sessions = try context.fetch(FetchDescriptor<FitOutSchemaV4.SessionRecord>()).map { record in
            guard let data = details[record.id] else { return record.value }
            return try JSONDecoder().decode(SessionPlanDetails.self, from: data).applying(to: record.value)
        }.sorted { $0.startedAt > $1.startedAt }
    }
    @discardableResult func start(day: RoutineDay? = nil, routineID: UUID? = nil, catalogue: [ExerciseDefinition], now: Date = .now) -> Bool {
        guard active == nil else { error = "Resume or end the current workout first."; return false }
        do {
            let session = try day.map { try PlannedWorkoutFactory.make(day: $0, routineID: routineID, catalogue: catalogue, now: now) }
                ?? WorkoutSession(title: "Quick workout", startedAt: now)
            return save(session)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func update(_ mutation: (inout WorkoutSession) -> Void) -> Bool {
        guard var session = active else { error = "No active workout."; return false }
        mutation(&session); return save(session)
    }
    func pause(now: Date = .now) { guard active?.status == .inProgress else { return }; update { $0.status = .paused; $0.pausedAt = now } }
    func resume(now: Date = .now) {
        guard active?.status == .paused else { return }
        update {
            if let pause = $0.pausedAt {
                let elapsed = max(0, now.timeIntervalSince(pause))
                $0.pausedSeconds += elapsed
                if let deadline = $0.restUntil {
                    $0.restUntil = deadline > pause ? deadline.addingTimeInterval(elapsed) : nil
                }
            }
            $0.pausedAt = nil; $0.status = .inProgress
        }
    }
    @discardableResult func finish(_ status: SessionStatus, now: Date = .now) -> Bool {
        guard [.completed, .skipped, .abandoned].contains(status), let active else { return false }
        if status == .completed && active.completedSets.isEmpty { error = "Complete at least one set, or mark the workout skipped or abandoned."; return false }
        return update {
            if let pause = $0.pausedAt { $0.pausedSeconds += max(0, now.timeIntervalSince(pause)) }
            $0.pausedAt = nil; $0.endedAt = now; $0.status = status; $0.restUntil = nil
        }
    }
    func add(_ exercise: ExerciseDefinition) { add([exercise]) }
    @discardableResult func add(_ exercises: [ExerciseDefinition]) -> Bool {
        guard !exercises.isEmpty else { return false }
        return update { session in
            session.entries.append(contentsOf: exercises.map { WorkoutEntry(exercise: $0, sets: [WorkoutSet()]) })
        }
    }
    func replace(entryID: UUID, with exercise: ExerciseDefinition) {
        guard let entry = active?.entries.first(where: { $0.id == entryID }), !entry.sets.contains(where: { $0.completedAt != nil }) else { error = "This exercise has logged sets. Add the alternative as a new exercise to preserve them."; return }
        update { session in if let i = session.entries.firstIndex(where: { $0.id == entryID }) { session.entries[i] = WorkoutEntry(exercise: exercise, sets: [WorkoutSet()]) } }
    }
    func toggleSet(entryID: UUID, setID: UUID, now: Date = .now) {
        guard active?.status == .inProgress else { error = "Resume the workout before completing a set."; return }
        guard let entry = active?.entries.first(where: { $0.id == entryID }), let set = entry.sets.first(where: { $0.id == setID }) else { return }
        if set.completedAt == nil && (entry.exercise.kind == .duration ? set.seconds <= 0 : set.reps <= 0) { error = "Enter positive reps or duration before completing this set."; return }
        update { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            let completing = session.entries[e].sets[s].completedAt == nil
            session.entries[e].sets[s].completedAt = completing ? now : nil
            let rest = set.restSeconds ?? entry.restSeconds
            session.restUntil = completing && rest > 0 ? now.addingTimeInterval(Double(rest)) : nil
        }
    }
    @discardableResult func delete(_ id: UUID) -> Bool {
        do {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV4.SessionRecord>()).first(where: { $0.id == id }) { context.delete(record) }
            if let detail = try context.fetch(FetchDescriptor<FitOutSchemaV5.SessionDetails>()).first(where: { $0.id == id }) { context.delete(detail) }
            try context.save(); try reload(); onChange?(); return true
        }
        catch { context.rollback(); self.error = error.localizedDescription; return false }
    }
    private func save(_ session: WorkoutSession) -> Bool {
        guard session.entries.flatMap(\.sets).allSatisfy(\.isValid) else { error = "Check reps, load, duration, distance and RPE. Values must be finite and within the supported range."; return false }
        do {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV4.SessionRecord>()).first(where: { $0.id == session.id }) {
                for entry in record.entries { context.delete(entry) }
                record.title = session.title; record.endedAt = session.endedAt; record.status = session.status.rawValue; record.pausedAt = session.pausedAt; record.pausedSeconds = session.pausedSeconds; record.restUntil = session.restUntil; record.notes = session.notes
                record.entries = session.entries.enumerated().map { FitOutSchemaV4.EntryRecord($0.element, position: $0.offset) }
            } else { context.insert(FitOutSchemaV4.SessionRecord(session)) }
            let payload = try JSONEncoder().encode(SessionPlanDetails(session))
            if let details = try context.fetch(FetchDescriptor<FitOutSchemaV5.SessionDetails>()).first(where: { $0.id == session.id }) {
                details.payload = payload
            } else { context.insert(FitOutSchemaV5.SessionDetails(id: session.id, payload: payload)) }
            try context.save(); try reload(); error = nil; onChange?(); return true
        } catch { context.rollback(); self.error = error.localizedDescription; return false }
    }
}

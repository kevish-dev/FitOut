import Foundation
import SwiftData
import Observation

@MainActor @Observable final class WorkoutStore {
    private let context: ModelContext
    private(set) var sessions: [WorkoutSession] = []
    var error: String?
    var onChange: (() -> Void)?
    private(set) var visibleEditorCount = 0
    var onEditorVisibilityChange: (() -> Void)?
    func editorAppeared() { visibleEditorCount += 1; onEditorVisibilityChange?() }
    func editorDisappeared() { visibleEditorCount = max(0, visibleEditorCount - 1); onEditorVisibilityChange?() }
    init(container: ModelContainer) throws {
        context = ModelContext(container); context.autosaveEnabled = false; try reload()
        if var active, active.telemetry == nil || active.inputMemoryVersion == nil {
            if active.inputMemoryVersion == nil {
                // Old sessions cannot tell us which pending inputs were edited.
                // Preserve them conservatively; explicit reuse is still available.
                for e in active.entries.indices {
                    for s in active.entries[e].sets.indices where active.entries[e].sets[s].completedAt == nil {
                        active.entries[e].sets[s].editedInputs = [.load, .reps, .seconds, .distance]
                    }
                }
                active.inputMemoryVersion = 1
            }
            if !save(active, before: active) { throw ValidationError(message: error ?? "Workout tracking could not be saved.") }
        }
    }
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
            var session = try day.map { try PlannedWorkoutFactory.make(day: $0, routineID: routineID, catalogue: catalogue, now: now) }
                ?? WorkoutSession(title: "Quick workout", startedAt: now)
            session.entries = session.entries.map { WorkoutRecall.seeded($0, current: nil, history: history) }
            session.inputMemoryVersion = 1
            WorkoutExecutionEngine.prepare(&session, at: now)
            return save(session, at: now)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func update(at now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil, recordInputEdits: Bool = true, _ mutation: (inout WorkoutSession) -> Void) -> Bool {
        guard var session = active else { error = "No active workout."; return false }
        if let receipt, session.telemetry?.actionReceipts.contains(receipt) == true { return true }
        let previous = session
        if session.telemetry == nil { session.telemetry = WorkoutTelemetry(recordedSince: now, baselinePausedSeconds: session.pausedSeconds) }
        if session.status == .inProgress, let deadline = session.restUntil, deadline <= now { session.restUntil = nil }
        mutation(&session)
        if recordInputEdits { WorkoutRecall.protectEdits(in: &session, comparedTo: previous) }
        if let receipt {
            session.telemetry?.actionReceipts.append(receipt)
        }
        return save(session, before: previous, at: now, origin: origin)
    }
    @discardableResult func pause(now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        guard active != nil else { return false }
        return update(at: now, origin: origin, receipt: receipt) {
            WorkoutExecutionEngine.prepare(&$0, at: now)
            if $0.status == .inProgress {
                let previousPhase = $0.execution?.phase
                $0.execution?.resumePhase = previousPhase; $0.execution?.phase = .paused
                $0.status = .paused; $0.pausedAt = now
            }
        }
    }
    @discardableResult func resume(now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        guard active != nil else { return false }
        return update(at: now, origin: origin, receipt: receipt) {
            guard $0.status == .paused else { return }
            if let pause = $0.pausedAt {
                let elapsed = max(0, now.timeIntervalSince(pause))
                $0.pausedSeconds += elapsed
                if let deadline = $0.restUntil {
                    $0.restUntil = deadline > pause ? deadline.addingTimeInterval(elapsed) : nil
                }
            }
            $0.pausedAt = nil; $0.status = .inProgress
            WorkoutExecutionEngine.prepare(&$0, at: now)
        }
    }
    @discardableResult func finish(_ status: SessionStatus, now: Date = .now) -> Bool {
        guard [.completed, .skipped, .abandoned].contains(status), let active else { return false }
        if status == .completed && active.completedSets.isEmpty { error = "Complete at least one set, or mark the workout skipped or abandoned."; return false }
        return update(at: now) {
            if let pause = $0.pausedAt { $0.pausedSeconds += max(0, now.timeIntervalSince(pause)) }
            $0.pausedAt = nil; $0.endedAt = now; $0.status = status; $0.restUntil = nil
        }
    }
    func add(_ exercise: ExerciseDefinition) { add([exercise]) }
    @discardableResult func add(_ exercises: [ExerciseDefinition]) -> Bool {
        guard !exercises.isEmpty else { return false }
        return update { session in
            let additions = exercises.map {
                WorkoutRecall.seeded(WorkoutEntry(exercise: $0, sets: [WorkoutSet()]), current: session, history: history)
            }
            session.entries.append(contentsOf: additions)
            WorkoutExecutionEngine.prepare(&session, at: .now)
        }
    }
    func replace(entryID: UUID, with exercise: ExerciseDefinition) {
        guard let entry = active?.entries.first(where: { $0.id == entryID }), !entry.sets.contains(where: { $0.completedAt != nil }) else { error = "This exercise has logged sets. Add the alternative as a new exercise to preserve them."; return }
        update { session in if let i = session.entries.firstIndex(where: { $0.id == entryID }) {
            session.entries[i] = WorkoutRecall.seeded(WorkoutEntry(exercise: exercise, sets: [WorkoutSet()]), current: session, history: history)
        } }
    }
    func reference(entryID: UUID, setID: UUID) -> WorkoutSetReference? {
        guard let active, let entry = active.entries.first(where: { $0.id == entryID }) else { return nil }
        return WorkoutRecall.reference(for: entry, setID: setID, current: active, history: history)
    }
    @discardableResult func reusePrevious(entryID: UUID, setID: UUID) -> Bool {
        guard let source = reference(entryID: entryID, setID: setID), let entry = active?.entries.first(where: { $0.id == entryID }),
              let set = entry.sets.first(where: { $0.id == setID }), set.completedAt == nil, set.startedAt == nil else { return false }
        return update { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            session.entries[e].sets[s] = WorkoutRecall.copyInputs(session.entries[e].sets[s], from: source.set, kind: entry.exercise.kind)
        }
    }
    @discardableResult func appendSet(entryID: UUID) -> Bool {
        guard let entry = active?.entries.first(where: { $0.id == entryID }), !entry.skipped else { return false }
        return update { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }) else { return }
            let lastWorking = entry.sets.last(where: { $0.type == .working })
            var set = lastWorking?.nextWorkingSet() ?? WorkoutSet()
            set.restSeconds = lastWorking?.restSeconds
            if entry.sets.allSatisfy({ $0.type != .working }) {
                let candidate = WorkoutEntry(exercise: entry.exercise, sets: [set])
                set = WorkoutRecall.seeded(candidate, current: session, history: history).sets[0]
            }
            session.entries[e].sets.append(set)
        }
    }
    @discardableResult func repeatInputs(entryID: UUID, setID: UUID) -> Bool {
        guard let entry = active?.entries.first(where: { $0.id == entryID && !$0.skipped }),
              let index = entry.sets.firstIndex(where: { $0.id == setID }), entry.sets[index].isValid else { return false }
        let source = entry.sets[index], kind = entry.exercise.kind
        if kind == .duration, source.seconds <= 0 || (source.startedAt != nil && source.timedActiveSeconds == nil) { return false }
        return update { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }) else { return }
            for s in session.entries[e].sets.indices where s > index {
                let target = session.entries[e].sets[s]
                guard target.type == source.type, target.completedAt == nil, target.startedAt == nil else { continue }
                if kind == .weighted {
                    session.entries[e].sets[s].loadKG = source.loadKG
                    session.entries[e].sets[s].editedInputs = (target.editedInputs ?? []).union([.load])
                } else {
                    session.entries[e].sets[s] = WorkoutRecall.copyInputs(target, from: source, kind: kind)
                }
            }
        }
    }
    func toggleSet(entryID: UUID, setID: UUID, now: Date = .now) {
        guard active?.status == .inProgress else { error = "Resume the workout before completing a set."; return }
        guard let entry = active?.entries.first(where: { $0.id == entryID }), let set = entry.sets.first(where: { $0.id == setID }) else { return }
        let timedSeconds = set.timedActiveSeconds == nil ? set.startedActiveSeconds.map { max(0, (active?.duration(at: now) ?? 0) - $0) } : nil
        if set.completedAt == nil && (entry.exercise.kind == .duration ? (timedSeconds ?? set.seconds) <= 0 : set.reps <= 0) { error = "Enter positive reps or duration before completing this set."; return }
        update(at: now, recordInputEdits: false) { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            let completing = session.entries[e].sets[s].completedAt == nil
            if completing, entry.exercise.kind == .duration, let timedSeconds { session.entries[e].sets[s].seconds = timedSeconds }
            session.entries[e].sets[s].completedAt = completing ? now : nil
            if !completing {
                session.entries[e].sets[s].startedAt = nil; session.entries[e].sets[s].startedActiveSeconds = nil
                session.entries[e].sets[s].timedActiveSeconds = nil; session.entries[e].sets[s].loggedActiveSeconds = nil
            }
            let rest = set.restSeconds ?? entry.restSeconds
            session.restUntil = completing && rest > 0 ? now.addingTimeInterval(Double(rest)) : nil
            if completing {
                let source = session.entries[e].sets[s]
                for next in session.entries[e].sets.indices where next > s && session.entries[e].sets[next].type == source.type {
                    session.entries[e].sets[next] = WorkoutRecall.filling(session.entries[e].sets[next], from: source, kind: entry.exercise.kind, fields: source.editedInputs ?? [])
                }
            }
        }
    }
    @discardableResult func startSet(entryID: UUID, setID: UUID, now: Date = .now) -> Bool {
        guard let current = active, current.status == .inProgress,
              let entry = current.entries.first(where: { $0.id == entryID && !$0.skipped }),
              let set = entry.sets.first(where: { $0.id == setID && $0.completedAt == nil }) else { return false }
        return update(at: now, recordInputEdits: false) { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            // A set timer follows the current set. Switching preserves the earlier
            // measurement without logging a set the person has not confirmed.
            for otherEntry in session.entries.indices {
                for otherSet in session.entries[otherEntry].sets.indices {
                    let previous = session.entries[otherEntry].sets[otherSet]
                    guard previous.id != setID, previous.completedAt == nil, previous.startedAt != nil,
                          previous.timedActiveSeconds == nil, let elapsed = session.setElapsed(previous, at: now) else { continue }
                    session.entries[otherEntry].sets[otherSet].timedActiveSeconds = elapsed
                    if session.entries[otherEntry].exercise.kind == .duration { session.entries[otherEntry].sets[otherSet].seconds = elapsed }
                }
            }
            if set.startedAt == nil || set.timedActiveSeconds != nil {
                session.entries[e].sets[s].startedAt = now
                session.entries[e].sets[s].startedActiveSeconds = session.duration(at: now)
                session.entries[e].sets[s].timedActiveSeconds = nil
            }
            session.telemetry?.focusedEntryID = entryID; session.telemetry?.focusedSetID = setID
            session.restUntil = nil
        }
    }
    @discardableResult func stopSetTimer(entryID: UUID, setID: UUID, now: Date = .now) -> Bool {
        guard let current = active, let entry = current.entries.first(where: { $0.id == entryID }),
              let set = entry.sets.first(where: { $0.id == setID && $0.completedAt == nil }),
              let elapsed = current.setElapsed(set, at: now) else { return false }
        return update(at: now, recordInputEdits: false) { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            session.entries[e].sets[s].timedActiveSeconds = elapsed
            if entry.exercise.kind == .duration { session.entries[e].sets[s].seconds = elapsed }
        }
    }
    @discardableResult func endRest(now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        if let active, active.execution?.phase == .resting {
            return performFocused(.skipRest, sessionID: active.id, now: now, origin: origin, receipt: receipt)
        }
        return update(at: now, origin: origin, receipt: receipt) { $0.restUntil = nil }
    }
    @discardableResult func runQuickAction(_ operation: String, sessionID: UUID, commandID: UUID, now: Date = .now) -> Bool {
        guard active?.id == sessionID else { error = "This workout has ended. Open FitOut for the current session."; return false }
        let key = commandID.uuidString + ":" + operation
        if active?.telemetry?.actionReceipts.contains(key) == true { return true }
        if ["startSet", "extendRest", "endRest"].contains(operation), active?.telemetry?.revision != commandID { return true }
        switch operation {
        case "pause": return pause(now: now, origin: .liveActivity, receipt: key)
        case "resume": return resume(now: now, origin: .liveActivity, receipt: key)
        case "extendRest": return performFocused(.extendRest, sessionID: sessionID, now: now, origin: .liveActivity, receipt: key)
        case "startSet": return performFocused(.startSet, sessionID: sessionID, now: now, origin: .liveActivity, receipt: key)
        case "endRest": return endRest(now: now, origin: .liveActivity, receipt: key)
        default: error = "This workout action is unavailable."; return false
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
    func save(_ input: WorkoutSession, before: WorkoutSession? = nil, at now: Date = .now, origin: WorkoutEventOrigin = .app) -> Bool {
        let session = WorkoutTelemetryRecorder.prepare(input, before: before, at: now, origin: origin)
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

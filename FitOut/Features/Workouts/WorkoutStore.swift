import Foundation
import SwiftData
import Observation

@MainActor @Observable final class WorkoutStore {
    private let context: ModelContext
    private(set) var sessions: [WorkoutSession] = []
    var error: String?
    var onChange: (() -> Void)?
    private(set) var visibleEditorCount = 0
    func editorAppeared() { visibleEditorCount += 1 }
    func editorDisappeared() { visibleEditorCount = max(0, visibleEditorCount - 1) }
    init(container: ModelContainer) throws {
        context = ModelContext(container); context.autosaveEnabled = false; try reload()
        if let active, active.telemetry == nil, !save(active, before: active) {
            throw ValidationError(message: error ?? "Workout tracking could not be saved.")
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
            let session = try day.map { try PlannedWorkoutFactory.make(day: $0, routineID: routineID, catalogue: catalogue, now: now) }
                ?? WorkoutSession(title: "Quick workout", startedAt: now)
            return save(session, at: now)
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func update(at now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil, _ mutation: (inout WorkoutSession) -> Void) -> Bool {
        guard var session = active else { error = "No active workout."; return false }
        if let receipt, session.telemetry?.actionReceipts.contains(receipt) == true { return true }
        let previous = session
        if session.telemetry == nil { session.telemetry = WorkoutTelemetry(recordedSince: now, baselinePausedSeconds: session.pausedSeconds) }
        if session.status == .inProgress, let deadline = session.restUntil, deadline <= now { session.restUntil = nil }
        mutation(&session)
        if let receipt {
            session.telemetry?.actionReceipts.append(receipt)
        }
        return save(session, before: previous, at: now, origin: origin)
    }
    @discardableResult func pause(now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        guard active != nil else { return false }
        return update(at: now, origin: origin, receipt: receipt) { if $0.status == .inProgress { $0.status = .paused; $0.pausedAt = now } }
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
        let timedSeconds = set.timedActiveSeconds == nil ? set.startedActiveSeconds.map { max(0, (active?.duration(at: now) ?? 0) - $0) } : nil
        if set.completedAt == nil && (entry.exercise.kind == .duration ? (timedSeconds ?? set.seconds) <= 0 : set.reps <= 0) { error = "Enter positive reps or duration before completing this set."; return }
        update(at: now) { session in
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
        }
    }
    @discardableResult func startSet(entryID: UUID, setID: UUID, now: Date = .now) -> Bool {
        guard let current = active, current.status == .inProgress,
              let entry = current.entries.first(where: { $0.id == entryID && !$0.skipped }),
              let set = entry.sets.first(where: { $0.id == setID && $0.completedAt == nil }) else { return false }
        return update(at: now) { session in
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
        return update(at: now) { session in
            guard let e = session.entries.firstIndex(where: { $0.id == entryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            session.entries[e].sets[s].timedActiveSeconds = elapsed
            if entry.exercise.kind == .duration { session.entries[e].sets[s].seconds = elapsed }
        }
    }
    @discardableResult func markLap(now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        guard let active, active.status == .inProgress else { error = "Resume the workout to record a lap."; return false }
        return update(at: now, origin: origin, receipt: receipt) { session in
            guard var log = session.telemetry else { return }
            let previous = log.laps.last
            let elapsed = session.duration(at: now)
            let start = previous?.endedAt ?? session.startedAt
            log.laps.append(WorkoutLap(number: log.laps.count + 1, startedAt: start, endedAt: now,
                activeSeconds: max(0, elapsed - (previous?.elapsedActiveSeconds ?? 0)), wallSeconds: max(0, now.timeIntervalSince(start)),
                elapsedActiveSeconds: elapsed, entryID: session.focusedWork?.entry.id))
            session.telemetry = log
        }
    }
    @discardableResult func endRest(now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        update(at: now, origin: origin, receipt: receipt) { $0.restUntil = nil }
    }
    @discardableResult func runQuickAction(_ operation: String, sessionID: UUID, commandID: UUID, now: Date = .now) -> Bool {
        guard active?.id == sessionID else { error = "This workout has ended. Open FitOut for the current session."; return false }
        let key = commandID.uuidString + ":" + operation
        if active?.telemetry?.actionReceipts.contains(key) == true { return true }
        switch operation {
        case "pause": return pause(now: now, origin: .liveActivity, receipt: key)
        case "resume": return resume(now: now, origin: .liveActivity, receipt: key)
        case "lap": return markLap(now: now, origin: .liveActivity, receipt: key)
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
    private func save(_ input: WorkoutSession, before: WorkoutSession? = nil, at now: Date = .now, origin: WorkoutEventOrigin = .app) -> Bool {
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

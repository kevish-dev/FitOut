import Foundation

enum WorkoutPhase: String, Codable, Equatable {
    case ready, activeSet, resting, paused, exerciseTransition, workoutCompleted
}
enum WorkoutSetStatus: String { case pending, completed, skipped }
struct WorkoutActual: Codable, Equatable {
    var loadKG: Double
    var reps: Int
    var seconds: TimeInterval
    var distanceMeters: Double
    var isValid: Bool { loadKG.isFinite && (0...1000).contains(loadKG) && (0...1000).contains(reps)
        && seconds.isFinite && (0...86400).contains(seconds) && distanceMeters.isFinite && (0...1_000_000).contains(distanceMeters) }
}
struct WorkoutUndo: Codable, Equatable {
    var entryID: UUID
    var setID: UUID
    var before: WorkoutSet
    var date: Date
}
struct WorkoutExecution: Codable, Equatable {
    var phase: WorkoutPhase = .ready
    var resumePhase: WorkoutPhase?
    var entryID: UUID?
    var setID: UUID?
    var preferredUnit: WeightUnit?
    var undo: WorkoutUndo?
}
enum WorkoutCommand { case startSet, completeSet, skipSet, skipRest, extendRest, finish, undo }

extension WorkoutSet {
    var status: WorkoutSetStatus { skippedAt != nil ? .skipped : completedAt != nil ? .completed : .pending }
}
extension WorkoutSession {
    var skippedSets: [WorkoutSet] { entries.flatMap(\.sets).filter { $0.status == .skipped } }
    var pendingWork: [(entryID: UUID, setID: UUID)] {
        entries.filter { !$0.skipped }.flatMap { entry in entry.sets.filter { $0.status == .pending }.map { (entry.id, $0.id) } }
    }
    var executingWork: (entry: WorkoutEntry, set: WorkoutSet)? {
        guard let entry = entries.first(where: { $0.id == execution?.entryID }),
              let set = entry.sets.first(where: { $0.id == execution?.setID }) else { return nil }
        return (entry, set)
    }
}

/// Pure timestamp-driven transitions, shared by app UI, recovery and Live Activity actions.
enum WorkoutExecutionEngine {
    static func prepare(_ session: inout WorkoutSession, at now: Date) {
        if session.execution == nil {
            var execution = WorkoutExecution()
            if let latest = session.entries.flatMap({ entry in entry.sets.filter { $0.completedAt != nil }.map { (entry.id, $0) } })
                .max(by: { ($0.1.completedAt ?? .distantPast) < ($1.1.completedAt ?? .distantPast) }), session.restUntil != nil {
                execution.entryID = latest.0; execution.setID = latest.1.id; execution.phase = .resting
            } else if let focus = session.focusedWork {
                execution.entryID = focus.entry.id; execution.setID = focus.set.id
                if focus.set.startedAt != nil && focus.set.timedActiveSeconds == nil { execution.phase = .activeSet }
            } else { assignFirstPending(&execution, session: session) }
            session.execution = execution
        }
        guard var execution = session.execution else { return }
        if !session.isActive { execution.phase = .workoutCompleted; session.execution = execution; return }
        if session.status == .paused {
            if execution.phase != .paused { execution.resumePhase = execution.phase; execution.phase = .paused }
            session.execution = execution; return
        }
        if execution.phase == .paused { execution.phase = execution.resumePhase ?? .ready; execution.resumePhase = nil }
        if execution.phase == .resting {
            if session.restUntil.map({ $0 > now }) != true { session.restUntil = nil; advance(&execution, session: session) }
        } else if session.executingWork == nil || session.executingWork?.set.status != .pending {
            assignFirstPending(&execution, session: session); execution.phase = .ready
        }
        session.execution = execution
        session.telemetry?.focusedEntryID = execution.entryID; session.telemetry?.focusedSetID = execution.setID
    }

    @discardableResult static func apply(_ command: WorkoutCommand, to session: inout WorkoutSession, expectedSet: UUID? = nil, at now: Date) throws -> Bool {
        prepare(&session, at: now)
        guard var execution = session.execution else { return false }
        if command == .undo { return undo(&session, execution: &execution, at: now) }
        guard session.isActive else { return false }
        if command == .finish {
            close(&session, execution: &execution, at: now); session.execution = execution; return true
        }
        guard session.status == .inProgress else { return false }
        if command == .skipRest {
            guard execution.phase == .resting else { return false }
            session.restUntil = nil; advance(&execution, session: session); session.execution = execution; return true
        }
        if command == .extendRest {
            guard execution.phase == .resting, let deadline = session.restUntil, deadline > now else { return false }
            session.restUntil = deadline.addingTimeInterval(15); return true
        }
        guard let e = session.entries.firstIndex(where: { $0.id == execution.entryID && !$0.skipped }),
              let s = session.entries[e].sets.firstIndex(where: { $0.id == execution.setID }),
              expectedSet == nil || expectedSet == execution.setID,
              session.entries[e].sets[s].status == .pending else { return false }
        if command == .startSet {
            guard [.ready, .exerciseTransition].contains(execution.phase) else { return false }
            session.entries[e].sets[s].startedAt = now
            session.entries[e].sets[s].startedActiveSeconds = session.duration(at: now)
            session.entries[e].sets[s].timedActiveSeconds = nil
            let target = session.entries[e].sets[s]
            session.entries[e].sets[s].inputTarget = WorkoutActual(loadKG: target.loadKG, reps: target.reps, seconds: target.seconds, distanceMeters: target.distanceMeters)
            session.restUntil = nil; execution.phase = .activeSet
            session.execution = execution; return true
        }
        guard command == .skipSet || execution.phase == .activeSet else { return false }
        guard [.ready, .activeSet, .exerciseTransition].contains(execution.phase) else { return false }
        let before = session.entries[e].sets[s]
        let elapsed = session.setElapsed(before, at: now) ?? 0
        let kind = session.entries[e].exercise.kind
        if command == .completeSet {
            guard before.isValid, kind == .duration ? elapsed > 0 : before.reps > 0 else {
                throw ValidationError(message: kind == .duration ? "Start the timer before recording a positive duration." : "Enter positive reps and a valid weight before completing this set.")
            }
            session.entries[e].sets[s].completedAt = now
            session.entries[e].sets[s].actual = WorkoutActual(loadKG: kind == .weighted ? before.loadKG : 0,
                reps: kind == .duration ? 0 : before.reps, seconds: elapsed, distanceMeters: before.distanceMeters)
            if kind == .duration { session.entries[e].sets[s].seconds = elapsed }
        } else {
            session.entries[e].sets[s].skippedAt = now
            session.entries[e].sets[s].actual = nil
        }
        if before.startedAt != nil { session.entries[e].sets[s].timedActiveSeconds = elapsed }
        execution.undo = WorkoutUndo(entryID: session.entries[e].id, setID: before.id, before: before, date: now)
        if command == .completeSet {
            let source = session.entries[e].sets[s]
            for index in session.entries[e].sets.indices where index > s && session.entries[e].sets[index].type == source.type {
                session.entries[e].sets[index] = WorkoutRecall.filling(session.entries[e].sets[index], from: source, kind: kind, fields: source.editedInputs ?? [])
            }
        }
        if session.pendingWork.isEmpty { close(&session, execution: &execution, at: now) }
        else if command == .completeSet, (before.restSeconds ?? session.entries[e].restSeconds) > 0 {
            session.restUntil = now.addingTimeInterval(Double(before.restSeconds ?? session.entries[e].restSeconds))
            execution.phase = .resting
        } else { session.restUntil = nil; advance(&execution, session: session) }
        session.execution = execution
        return true
    }

    private static func assignFirstPending(_ execution: inout WorkoutExecution, session: WorkoutSession) {
        execution.entryID = session.pendingWork.first?.entryID; execution.setID = session.pendingWork.first?.setID
    }
    private static func advance(_ execution: inout WorkoutExecution, session: WorkoutSession) {
        let previous = execution.entryID
        assignFirstPending(&execution, session: session)
        execution.phase = execution.entryID != nil && execution.entryID != previous ? .exerciseTransition : .ready
    }
    private static func close(_ session: inout WorkoutSession, execution: inout WorkoutExecution, at now: Date) {
        if let pause = session.pausedAt { session.pausedSeconds += max(0, now.timeIntervalSince(pause)) }
        session.pausedAt = nil; session.restUntil = nil; session.endedAt = now
        session.status = session.completedSets.isEmpty ? .skipped : .completed
        execution.phase = .workoutCompleted; execution.resumePhase = nil
    }
    private static func undo(_ session: inout WorkoutSession, execution: inout WorkoutExecution, at now: Date) -> Bool {
        guard let undo = execution.undo,
              let e = session.entries.firstIndex(where: { $0.id == undo.entryID }),
              let s = session.entries[e].sets.firstIndex(where: { $0.id == undo.setID }) else { return false }
        for entryIndex in session.entries.indices {
            for setIndex in session.entries[entryIndex].sets.indices {
                let pending = session.entries[entryIndex].sets[setIndex]
                if pending.id != undo.setID, pending.status == .pending, pending.timedActiveSeconds == nil,
                   let elapsed = session.setElapsed(pending, at: now) {
                    session.entries[entryIndex].sets[setIndex].timedActiveSeconds = elapsed
                }
            }
        }
        if let ended = session.endedAt { session.pausedSeconds += max(0, now.timeIntervalSince(ended)) }
        var restored = undo.before
        restored.startedAt = nil; restored.startedActiveSeconds = nil; restored.timedActiveSeconds = nil
        restored.loggedActiveSeconds = nil; restored.completedAt = nil; restored.skippedAt = nil; restored.actual = nil; restored.inputTarget = nil
        session.entries[e].sets[s] = restored; session.endedAt = nil; session.restUntil = nil
        execution.entryID = undo.entryID; execution.setID = undo.setID; execution.undo = nil
        if session.status == .paused { execution.phase = .paused; execution.resumePhase = .ready }
        else { session.status = .inProgress; execution.phase = .ready; execution.resumePhase = nil }
        session.execution = execution
        return true
    }
}

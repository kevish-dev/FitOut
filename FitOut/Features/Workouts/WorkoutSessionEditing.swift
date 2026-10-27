import Foundation

enum WorkoutSessionEdit {
    case reorder([UUID])
    case focus(UUID)
    case skip(UUID)
    case remove(UUID)
    case replace(UUID, ExerciseDefinition)
}

enum WorkoutSessionEditing {
    static func stopPendingTimers(_ session: inout WorkoutSession, at now: Date) {
        for e in session.entries.indices {
            for s in session.entries[e].sets.indices {
                let set = session.entries[e].sets[s]
                if set.status == .pending, set.timedActiveSeconds == nil, let elapsed = session.setElapsed(set, at: now) {
                    session.entries[e].sets[s].timedActiveSeconds = elapsed
                }
            }
        }
    }
    static func select(_ entryID: UUID?, session: inout WorkoutSession, now: Date) {
        let priorEntry = session.execution?.entryID
        stopPendingTimers(&session, at: now)
        let entry = session.entries.first { $0.id == entryID && !$0.skipped }
        let set = entry?.sets.first { $0.status == .pending }
        var execution = session.execution ?? WorkoutExecution()
        execution.entryID = entry?.id; execution.setID = set?.id
        let phase: WorkoutPhase = entry?.id != nil && entry?.id != priorEntry ? .exerciseTransition : .ready
        if session.status == .paused { execution.phase = .paused; execution.resumePhase = phase }
        else { execution.phase = phase; execution.resumePhase = nil }
        session.execution = execution; session.restUntil = nil
    }
    static func apply(_ command: WorkoutSessionEdit, to session: inout WorkoutSession,
                      history: [WorkoutSession], at now: Date) throws {
        guard session.isActive else { throw ValidationError(message: "This workout has ended. Start a new session to change exercises.") }
        WorkoutExecutionEngine.prepare(&session, at: now)
        if case .reorder(let ids) = command {
            guard ids.count == session.entries.count, Set(ids).count == ids.count,
                  Set(ids) == Set(session.entries.map(\.id)) else { throw ValidationError(message: "The exercise list changed. Try moving it again.") }
            guard ids != session.entries.map(\.id) else { return }
            let entries = Dictionary(uniqueKeysWithValues: session.entries.map { ($0.id, $0) })
            session.entries = ids.compactMap { entries[$0] }
            let phase = session.execution?.resumePhase ?? session.execution?.phase
            if [.ready, .exerciseTransition].contains(phase), session.executingWork?.set.startedAt == nil {
                select(session.pendingWork.first?.entryID, session: &session, now: now)
            }
            return
        }
        let id: UUID
        switch command {
        case .reorder: return
        case .focus(let value), .skip(let value), .remove(let value), .replace(let value, _): id = value
        }
        guard let index = session.entries.firstIndex(where: { $0.id == id }) else { throw ValidationError(message: "That exercise is no longer in this session.") }
        let original = session.entries[index]
        let pending = original.sets.filter { $0.status == .pending }
        let isCurrent = session.execution?.entryID == id
        if case .focus = command {
            guard !original.skipped, !pending.isEmpty else { throw ValidationError(message: "Choose an exercise with remaining sets.") }
            if isCurrent, session.execution?.phase == .activeSet { return }
            // Put this exercise at the front of the remaining queue. Earlier
            // unfinished exercises remain available after it, never marked done.
            session.entries.remove(at: index); session.entries.insert(original, at: 0)
            select(id, session: &session, now: now)
            return
        }
        guard !pending.isEmpty else { throw ValidationError(message: "This exercise has no remaining sets. Its records are kept.") }
        let records = original.sets.filter { $0.status != .pending }
        switch command {
        case .skip:
            for s in session.entries[index].sets.indices where session.entries[index].sets[s].status == .pending {
                let set = session.entries[index].sets[s]
                if set.timedActiveSeconds == nil, let elapsed = session.setElapsed(set, at: now) {
                    session.entries[index].sets[s].timedActiveSeconds = elapsed
                }
                session.entries[index].sets[s].skippedAt = now
                session.entries[index].sets[s].actual = nil
            }
            session.entries[index].skipped = true
        case .remove:
            if records.isEmpty { session.entries.remove(at: index) }
            else { session.entries[index].sets = records }
        case .replace(_, let exercise):
            guard exercise.id != original.exercise.id else { return }
            var replacement = WorkoutEntry(exercise: exercise, sets: pending.map { set in
                WorkoutSet(type: set.type, reps: exercise.kind == .duration ? 0 : original.exercise.kind == .duration ? 8 : max(1, set.plannedTarget?.repMin ?? set.reps),
                           seconds: exercise.kind == .duration ? 30 : 0, restSeconds: set.restSeconds ?? original.restSeconds)
            }, restSeconds: original.restSeconds)
            // Recall only the replacement exercise's own actual performance.
            replacement = WorkoutRecall.seeded(replacement, current: session, history: history)
            if records.isEmpty {
                replacement.id = original.id
                session.entries[index] = replacement
            } else {
                session.entries[index].sets = records
                session.entries.insert(replacement, at: index + 1)
            }
            if isCurrent { select(replacement.id, session: &session, now: now) }
        default: break
        }
        // A structural action cannot make old set-level Undo erase its result.
        session.execution?.undo = nil
        if isCurrent {
            switch command {
            case .replace: break // The replacement was selected above.
            default: select(session.pendingWork.first?.entryID, session: &session, now: now)
            }
        }
        // Editing the queue never silently finishes the workout. Finish remains
        // explicit when no pending work remains, preserving the summary flow.
        WorkoutExecutionEngine.prepare(&session, at: now)
    }
}

extension WorkoutStore {
    @discardableResult func editSession(_ command: WorkoutSessionEdit, sessionID: UUID, now: Date = .now) -> Bool {
        guard var session = active, session.id == sessionID else { error = "This workout is no longer active."; return false }
        let before = session
        do {
            try WorkoutSessionEditing.apply(command, to: &session, history: history, at: now)
            guard session != before else { error = nil; return true }
            return save(session, before: before, at: now)
        } catch { self.error = error.localizedDescription; return false }
    }
}

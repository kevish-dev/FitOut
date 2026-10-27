import Foundation

struct WorkoutRecordedSet: Identifiable, Equatable {
    let sessionID: UUID
    let entryID: UUID
    let exercise: ExerciseDefinition
    let number: Int
    let original: WorkoutSet
    var id: UUID { original.id }
}

extension WorkoutSession {
    func recordedSet(entryID: UUID, setID: UUID) -> WorkoutRecordedSet? {
        guard let entry = entries.first(where: { $0.id == entryID }),
              let index = entry.sets.firstIndex(where: { $0.id == setID && $0.status != .pending }) else { return nil }
        return WorkoutRecordedSet(sessionID: id, entryID: entry.id, exercise: entry.exercise, number: index + 1, original: entry.sets[index])
    }
    var lastRecordedSet: WorkoutRecordedSet? {
        let records = entries.flatMap { entry in entry.sets.compactMap { recordedSet(entryID: entry.id, setID: $0.id) } }
        return records.enumerated().max {
            let first = $0.element.original.completedAt ?? $0.element.original.skippedAt ?? .distantPast
            let second = $1.element.original.completedAt ?? $1.element.original.skippedAt ?? .distantPast
            return first == second ? $0.offset < $1.offset : first < second
        }?.element
    }
}

enum WorkoutRecordedSetEditing {
    static func corrected(_ proposed: WorkoutSet, original: WorkoutSet, kind: ExerciseKind) throws -> WorkoutSet {
        guard original.status != .pending, proposed.id == original.id, proposed.isValid,
              proposed.note.map({ $0.count <= 1000 }) ?? true,
              original.status == .skipped || (kind == .duration ? proposed.seconds > 0 : proposed.reps > 0) else {
            throw ValidationError(message: "Check the recorded reps, weight, time and effort. Completed sets need positive reps or duration.")
        }
        var result = original
        result.type = proposed.type; result.rpe = proposed.rpe; result.note = proposed.note
        switch kind {
        case .weighted: result.loadKG = proposed.loadKG; result.reps = proposed.reps
        case .bodyweight: result.reps = proposed.reps
        case .duration: result.seconds = proposed.seconds; result.distanceMeters = proposed.distanceMeters
        }
        if original.status == .completed, var actual = original.actual {
            if kind == .weighted { actual.loadKG = result.loadKG }
            if kind != .duration { actual.reps = result.reps }
            if kind == .duration { actual.seconds = result.seconds; actual.distanceMeters = result.distanceMeters }
            result.actual = actual
        }
        // Keep all timestamp/clock fields, plan targets, status, identity, and
        // pending sets exactly as they were. A legacy nil actual stays nil.
        return result
    }
}

extension WorkoutStore {
    @discardableResult func correctRecordedSet(_ proposed: WorkoutSet, reference: WorkoutRecordedSet, now: Date = .now) -> Bool {
        guard var session = sessions.first(where: { $0.id == reference.sessionID }),
              let e = session.entries.firstIndex(where: { $0.id == reference.entryID && $0.exercise == reference.exercise }),
              let s = session.entries[e].sets.firstIndex(where: { $0.id == reference.id }),
              session.entries[e].sets[s] == reference.original else {
            error = "This set changed while editing. Close and reopen it to see the latest record."; return false
        }
        let before = session
        do {
            session.entries[e].sets[s] = try WorkoutRecordedSetEditing.corrected(proposed, original: reference.original, kind: reference.exercise.kind)
            guard session != before else { error = nil; return true }
            // Never use update/prepare here: a correction must not advance or
            // reopen the session, end rest, or propagate into remaining targets.
            return save(session, before: before, at: now)
        } catch { self.error = error.localizedDescription; return false }
    }

    @discardableResult func restartRecordedSet(_ reference: WorkoutRecordedSet, now: Date = .now) -> Bool {
        guard active == nil || active?.id == reference.sessionID else {
            error = "Finish the current workout before restarting a set from another session."; return false
        }
        guard var session = sessions.first(where: { $0.id == reference.sessionID }),
              let e = session.entries.firstIndex(where: { $0.id == reference.entryID }),
              let s = session.entries[e].sets.firstIndex(where: { $0.id == reference.id }),
              session.entries[e].sets[s] == reference.original else {
            error = "This set has changed. Open its latest record before restarting."; return false
        }
        let before = session
        do {
            session.entries[e].skipped = false
            if session.execution == nil { session.execution = WorkoutExecution() }
            session.execution?.undo = WorkoutUndo(entryID: reference.entryID, setID: reference.id, before: reference.original, date: now)
            try WorkoutExecutionEngine.apply(.undo, to: &session, at: now)
            // Restart is explicit; a paused workout remains paused until Resume.
            if session.status == .inProgress { try WorkoutExecutionEngine.apply(.startSet, to: &session, at: now) }
            return save(session, before: before, at: now)
        } catch { self.error = error.localizedDescription; return false }
    }
}

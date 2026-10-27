import Foundation

enum WorkoutEventOrigin: String, Codable { case app, liveActivity }
enum WorkoutEventKind: String, Codable {
    case started, trackingEnabled, paused, resumed, lap, setCreated, setStarted, setTimerStopped, setLogged, setUndone, setEdited, setDeleted
    case exerciseAdded, exerciseRemoved, exerciseChanged, exerciseSkipped, exercisesReordered, exerciseFocused, setSkipped, notesChanged, restChanged, finished
    var title: String {
        switch self {
        case .started: "Workout started"; case .trackingEnabled: "Detailed tracking enabled"
        case .paused: "Paused"; case .resumed: "Resumed"; case .lap: "Lap recorded"
        case .setCreated: "Set added"; case .setStarted: "Set timer started"; case .setLogged: "Set logged"
        case .setTimerStopped: "Set timer stopped"
        case .setUndone: "Set undone"; case .setEdited: "Set updated"; case .setDeleted: "Set removed"
        case .setSkipped: "Set skipped"
        case .exerciseAdded: "Exercise added"; case .exerciseRemoved: "Exercise removed"
        case .exerciseChanged: "Exercise replaced"; case .exerciseSkipped: "Exercise availability changed"
        case .exercisesReordered: "Exercise order changed"; case .exerciseFocused: "Current exercise changed"
        case .notesChanged: "Notes updated"; case .restChanged: "Rest updated"; case .finished: "Workout ended"
        }
    }
}
struct WorkoutEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var activeSeconds: TimeInterval
    var kind: WorkoutEventKind
    var origin: WorkoutEventOrigin
    var exerciseName: String?
    var entryID: UUID?
    var setID: UUID?
    var beforeSet: WorkoutSet?
    var afterSet: WorkoutSet?
    var beforeText: String?
    var afterText: String?
    var beforeDeadline: Date?
    var afterDeadline: Date?
}
struct WorkoutPausePeriod: Identifiable, Codable, Equatable {
    var id = UUID()
    var startedAt: Date
    var endedAt: Date?
}
struct WorkoutLap: Identifiable, Codable, Equatable {
    var id = UUID()
    var number: Int
    var startedAt: Date
    var endedAt: Date
    var activeSeconds: TimeInterval
    var wallSeconds: TimeInterval
    var elapsedActiveSeconds: TimeInterval
    var entryID: UUID?
}
struct WorkoutTelemetry: Codable, Equatable {
    var recordedSince: Date
    var baselinePausedSeconds: TimeInterval
    var revision = UUID()
    var events: [WorkoutEvent] = []
    var pauses: [WorkoutPausePeriod] = []
    var laps: [WorkoutLap] = []
    var actionReceipts: [String] = []
    var focusedEntryID: UUID?
    var focusedSetID: UUID?
}

enum WorkoutTelemetryRecorder {
    static func prepare(_ input: WorkoutSession, before: WorkoutSession?, at now: Date, origin: WorkoutEventOrigin) -> WorkoutSession {
        var after = input
        var log = after.telemetry ?? before?.telemetry ?? WorkoutTelemetry(recordedSince: before == nil ? input.startedAt : now, baselinePausedSeconds: before?.pausedSeconds ?? 0)
        func event(_ kind: WorkoutEventKind, date: Date? = nil, activeSeconds: TimeInterval? = nil, entry: WorkoutEntry? = nil, set: UUID? = nil,
                   old: WorkoutSet? = nil, new: WorkoutSet? = nil, from: String? = nil, to: String? = nil,
                   beforeDeadline: Date? = nil, afterDeadline: Date? = nil) {
            var value = WorkoutEvent(date: date ?? now, activeSeconds: activeSeconds ?? after.duration(at: now), kind: kind, origin: origin,
                exerciseName: entry?.exercise.name, entryID: entry?.id, setID: set, beforeSet: old, afterSet: new,
                beforeText: from, afterText: to, beforeDeadline: beforeDeadline, afterDeadline: afterDeadline)
            // Typing commits form one edit record; explicit logging and clock actions never coalesce.
            if [.setEdited, .notesChanged].contains(kind), let last = log.events.last,
               last.kind == kind, last.entryID == value.entryID, last.setID == set, last.origin == origin,
               value.date.timeIntervalSince(last.date) >= 0, value.date.timeIntervalSince(last.date) < 2 {
                value.id = last.id; value.beforeSet = last.beforeSet; value.beforeText = last.beforeText
                log.events[log.events.count - 1] = value
            } else { log.events.append(value) }
        }
        if before == nil { event(.started, date: after.startedAt) }
        else if before?.telemetry == nil { event(.trackingEnabled) }
        if before?.status != after.status {
            if after.status == .paused {
                log.pauses.append(WorkoutPausePeriod(startedAt: after.pausedAt ?? now)); event(.paused)
            } else {
                if let start = before?.pausedAt {
                    if let index = log.pauses.lastIndex(where: { $0.endedAt == nil }) { log.pauses[index].endedAt = after.endedAt ?? now }
                    else { log.pauses.append(WorkoutPausePeriod(startedAt: start, endedAt: after.endedAt ?? now)) }
                }
                if before?.status == .paused && after.isActive { event(.resumed) }
                if !after.isActive { event(.finished, to: after.status.rawValue) }
            }
        }
        let previousEntries = Dictionary((before?.entries ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let before, Set(before.entries.map(\.id)) == Set(after.entries.map(\.id)), before.entries.map(\.id) != after.entries.map(\.id) {
            event(.exercisesReordered, from: before.entries.map { $0.exercise.name }.joined(separator: " → "), to: after.entries.map { $0.exercise.name }.joined(separator: " → "))
        }
        if let before, before.execution?.entryID != after.execution?.entryID,
           let current = after.entries.first(where: { $0.id == after.execution?.entryID }) { event(.exerciseFocused, entry: current) }
        for index in after.entries.indices {
            if after.entries[index].skipped || !after.isActive {
                for setIndex in after.entries[index].sets.indices {
                    let set = after.entries[index].sets[setIndex]
                    if set.completedAt == nil, set.timedActiveSeconds == nil, let elapsed = after.setElapsed(set, at: now) {
                        after.entries[index].sets[setIndex].timedActiveSeconds = elapsed
                        if after.entries[index].exercise.kind == .duration { after.entries[index].sets[setIndex].seconds = elapsed }
                    }
                }
            }
            let entry = after.entries[index]
            let previous = previousEntries[entry.id]
            if previous == nil { event(.exerciseAdded, entry: entry, to: entry.exercise.name) }
            else {
                if previous?.exercise != entry.exercise { event(.exerciseChanged, entry: entry, from: previous?.exercise.name, to: entry.exercise.name) }
                if previous?.skipped != entry.skipped { event(.exerciseSkipped, entry: entry, to: entry.skipped ? "Skipped; logged sets kept" : "Restored") }
                if previous?.notes != entry.notes { event(.notesChanged, entry: entry, from: previous?.notes, to: entry.notes) }
            }
            let oldSets = Dictionary((previous?.sets ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for setIndex in entry.sets.indices {
                var set = after.entries[index].sets[setIndex]
                let old = oldSets[set.id]
                if set.completedAt != old?.completedAt {
                    set.loggedActiveSeconds = set.completedAt.map { after.duration(at: $0) }
                    if let start = set.startedActiveSeconds, set.completedAt != nil, set.timedActiveSeconds == nil {
                        set.timedActiveSeconds = max(0, (set.loggedActiveSeconds ?? start) - start)
                    }
                    after.entries[index].sets[setIndex] = set
                }
                if old == nil { event(.setCreated, entry: entry, set: set.id, new: set) }
                else if old?.completedAt != set.completedAt { event(set.completedAt == nil ? .setUndone : .setLogged, entry: entry, set: set.id, old: old, new: set) }
                else if old?.skippedAt != set.skippedAt { event(set.skippedAt == nil ? .setUndone : .setSkipped, entry: entry, set: set.id, old: old, new: set) }
                else if old?.startedAt != set.startedAt { event(.setStarted, entry: entry, set: set.id, old: old, new: set) }
                else if old?.timedActiveSeconds != set.timedActiveSeconds { event(.setTimerStopped, entry: entry, set: set.id, old: old, new: set) }
                else if old != set { event(.setEdited, entry: entry, set: set.id, old: old, new: set) }
            }
            for old in previous?.sets ?? [] where !entry.sets.contains(where: { $0.id == old.id }) { event(.setDeleted, entry: entry, set: old.id, old: old) }
        }
        for old in before?.entries ?? [] where !after.entries.contains(where: { $0.id == old.id }) {
            event(.exerciseRemoved, entry: old, from: old.exercise.name)
            for set in old.sets { event(.setDeleted, entry: old, set: set.id, old: set) }
        }
        if before?.notes != after.notes, !(before == nil && after.notes.isEmpty) { event(.notesChanged, from: before?.notes, to: after.notes) }
        if let before, before.restUntil != after.restUntil {
            let expired = before.status == .inProgress && (before.restUntil.map { $0 <= now } ?? false)
            if expired, let deadline = before.restUntil {
                let recordedDate = max(deadline, log.recordedSince)
                event(.restChanged, date: recordedDate, activeSeconds: before.duration(at: recordedDate), from: "Rest elapsed",
                      beforeDeadline: deadline)
            }
            if !expired || after.restUntil != nil {
                event(.restChanged, beforeDeadline: expired ? nil : before.restUntil, afterDeadline: after.restUntil)
            }
        }
        let oldLaps = Set(before?.telemetry?.laps.map(\.id) ?? [])
        for lap in log.laps where !oldLaps.contains(lap.id) { event(.lap, date: lap.endedAt, to: "Lap \(lap.number) · \(lap.activeSeconds.formatted()) active seconds") }
        log.revision = UUID()
        after.telemetry = log
        return after
    }
}

extension WorkoutSession {
    func totalPaused(at now: Date = .now) -> TimeInterval {
        pausedSeconds + (pausedAt.map { max(0, (endedAt ?? now).timeIntervalSince($0)) } ?? 0)
    }
    func setElapsed(_ set: WorkoutSet, at now: Date = .now) -> TimeInterval? {
        if let recorded = set.timedActiveSeconds { return recorded }
        guard let start = set.startedActiveSeconds else { return nil }
        return max(0, (set.loggedActiveSeconds ?? duration(at: now)) - start)
    }
    var focusedWork: (entry: WorkoutEntry, set: WorkoutSet)? {
        if let current = executingWork { return current }
        if let entry = entries.first(where: { $0.id == telemetry?.focusedEntryID && !$0.skipped }),
           let set = entry.sets.first(where: { $0.id == telemetry?.focusedSetID && $0.status == .pending }) { return (entry, set) }
        for entry in entries where !entry.skipped { if let set = entry.sets.first(where: { $0.status == .pending }) { return (entry, set) } }
        return nil
    }
}

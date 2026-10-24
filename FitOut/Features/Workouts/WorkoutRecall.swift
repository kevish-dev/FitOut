import Foundation

enum WorkoutInputField: String, Codable, Hashable { case load, reps, seconds, distance }

struct WorkoutSetReference {
    var set: WorkoutSet
    var date: Date
    var restSeconds: Int
    var isCurrentWorkout: Bool
}

/// Suggestions come from confirmed sets of the same exercise, kind and set type.
/// Warm-ups, working sets and drop sets never supply defaults for each other.
enum WorkoutRecall {
    static func reference(for entry: WorkoutEntry, setID: UUID, current: WorkoutSession?, history: [WorkoutSession]) -> WorkoutSetReference? {
        guard let index = entry.sets.firstIndex(where: { $0.id == setID }) else { return nil }
        let target = entry.sets[index]
        func matches(_ candidate: WorkoutEntry) -> Bool {
            candidate.exercise.id == entry.exercise.id && candidate.exercise.kind == entry.exercise.kind
        }
        func valid(_ set: WorkoutSet) -> Bool {
            set.type == target.type && set.completedAt != nil && set.isValid
                && (entry.exercise.kind == .duration ? set.seconds > 0 : set.reps > 0)
        }
        if target.completedAt == nil, let current {
            let candidates = current.entries.filter(matches).flatMap { candidate in
                // Later sets may have been logged out of order; do not use them
                // to overwrite earlier set targets within this exercise entry.
                (candidate.id == entry.id ? Array(entry.sets.prefix(index)) : candidate.sets)
                    .filter(valid).map { WorkoutSetReference(set: $0, date: $0.completedAt!, restSeconds: $0.restSeconds ?? candidate.restSeconds, isCurrentWorkout: true) }
            }
            if let latest = candidates.max(by: { $0.date < $1.date }) { return latest }
        }
        let ordinal = entry.sets.prefix(index).filter { $0.type == target.type }.count
        let candidates = history.filter { !$0.isActive && $0.status != .skipped && $0.id != current?.id }.flatMap { session in
            session.entries.filter(matches).compactMap { candidate -> (Date, [WorkoutSet], Int)? in
                let sets = candidate.sets.filter(valid)
                guard let date = sets.compactMap(\.completedAt).max() else { return nil }
                return (date, sets, candidate.restSeconds)
            }
        }
        guard let latest = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        let set = latest.1[min(ordinal, latest.1.count - 1)]
        return WorkoutSetReference(set: set, date: set.completedAt!, restSeconds: set.restSeconds ?? latest.2, isCurrentWorkout: false)
    }

    static func seeded(_ input: WorkoutEntry, current: WorkoutSession?, history: [WorkoutSession]) -> WorkoutEntry {
        var entry = input
        for index in entry.sets.indices {
            guard let source = reference(for: entry, setID: entry.sets[index].id, current: current, history: history) else { continue }
            entry.sets[index] = filling(entry.sets[index], from: source.set, kind: entry.exercise.kind)
            if entry.sets[index].plannedTarget == nil {
                entry.sets[index].restSeconds = source.restSeconds
                entry.restSeconds = source.restSeconds
            }
        }
        return entry
    }

    /// Routine prescriptions win over defaults, including an explicit zero load.
    /// User edits and measurements already in progress also win over suggestions.
    static func filling(_ target: WorkoutSet, from source: WorkoutSet, kind: ExerciseKind,
                        fields: Set<WorkoutInputField> = [.load, .reps, .seconds, .distance]) -> WorkoutSet {
        guard target.completedAt == nil, target.startedAt == nil else { return target }
        var result = target
        let protected = target.editedInputs ?? []
        if kind == .weighted, fields.contains(.load), !protected.contains(.load), target.plannedTarget?.loadKG == nil { result.loadKG = source.loadKG }
        if target.plannedTarget == nil {
            if kind != .duration, fields.contains(.reps), !protected.contains(.reps) { result.reps = source.reps }
            if kind == .duration {
                if fields.contains(.seconds), !protected.contains(.seconds) { result.seconds = source.seconds }
                if fields.contains(.distance), !protected.contains(.distance) { result.distanceMeters = source.distanceMeters }
            }
        }
        return result
    }

    static func copyInputs(_ target: WorkoutSet, from source: WorkoutSet, kind: ExerciseKind) -> WorkoutSet {
        var result = target
        // Copy values only: completion, effort, timers and prescriptions stay local.
        switch kind {
        case .weighted: result.loadKG = source.loadKG; result.reps = source.reps
        case .bodyweight: result.reps = source.reps
        case .duration: result.seconds = source.seconds; result.distanceMeters = source.distanceMeters
        }
        let fields: Set<WorkoutInputField> = kind == .duration ? [.seconds, .distance] : kind == .weighted ? [.load, .reps] : [.reps]
        result.editedInputs = (result.editedInputs ?? []).union(fields)
        return result
    }

    static func protectEdits(in session: inout WorkoutSession, comparedTo before: WorkoutSession) {
        let oldSets = Dictionary(before.entries.flatMap(\.sets).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for e in session.entries.indices {
            for s in session.entries[e].sets.indices {
                var value = session.entries[e].sets[s]
                guard let old = oldSets[value.id] else { continue }
                var fields = value.editedInputs ?? []
                if value.loadKG != old.loadKG { fields.insert(.load) }
                if value.reps != old.reps { fields.insert(.reps) }
                if value.seconds != old.seconds { fields.insert(.seconds) }
                if value.distanceMeters != old.distanceMeters { fields.insert(.distance) }
                if !fields.isEmpty { value.editedInputs = fields }
                session.entries[e].sets[s] = value
            }
        }
    }
}

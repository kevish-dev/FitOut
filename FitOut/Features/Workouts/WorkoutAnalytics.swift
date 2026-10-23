import Foundation

struct StrengthRecord: Equatable {
    var maxLoadKG: Double?
    var estimated1RM: Double?
    var repsAtLoad: [Double: Int] = [:]
}
struct AnalyticsPoint: Identifiable { var date: Date; var value: Double; var id: Date { date } }
enum WorkoutAnalytics {
    static func qualifying(_ entry: WorkoutEntry) -> [WorkoutSet] { entry.exercise.kind == .weighted ? entry.sets.filter { $0.completedAt != nil && $0.type != .warmup && $0.isValid && $0.reps > 0 && $0.loadKG > 0 } : [] }
    static func estimate1RM(load: Double, reps: Int) -> Double? { guard load.isFinite, load > 0, (1...10).contains(reps) else { return nil }; return reps == 1 ? load : load * (1 + Double(reps) / 30) }
    static func records(exerciseID: String, sessions: [WorkoutSession]) -> StrengthRecord {
        let sets = sessions.filter { $0.status == .completed }.flatMap(\.entries).filter { $0.exercise.id == exerciseID }.flatMap(qualifying)
        var result = StrengthRecord(maxLoadKG: sets.map(\.loadKG).max(), estimated1RM: sets.compactMap { estimate1RM(load: $0.loadKG, reps: $0.reps) }.max())
        for set in sets { result.repsAtLoad[set.loadKG] = max(result.repsAtLoad[set.loadKG] ?? 0, set.reps) }
        return result
    }
    static func newRecords(in session: WorkoutSession, history: [WorkoutSession]) -> [String] {
        guard session.status == .completed else { return [] }
        let before = history.filter { $0.id != session.id && $0.startedAt < session.startedAt }
        return session.entries.compactMap { entry in
            let old = records(exerciseID: entry.exercise.id, sessions: before)
            let current = records(exerciseID: entry.exercise.id, sessions: [session])
            let load = (current.maxLoadKG ?? 0) > (old.maxLoadKG ?? 0)
            let reps = current.repsAtLoad.contains { $0.value > (old.repsAtLoad[$0.key] ?? 0) }
            let estimate = (current.estimated1RM ?? 0) > (old.estimated1RM ?? 0)
            return load || reps || estimate ? entry.exercise.name : nil
        }
    }
    static func weeklyVolumes(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> [AnalyticsPoint] {
        let groups = Dictionary(grouping: sessions.filter { $0.status == .completed }) { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)!.start }
        return groups.map { AnalyticsPoint(date: $0.key, value: $0.value.reduce(0) { $0 + $1.volumeKG }) }.sorted { $0.date < $1.date }
    }
    static func weeklyStreak(_ sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current) -> Int {
        let weeks = Set(sessions.filter { $0.status == .completed && $0.startedAt <= now }.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(week) { week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)! }
        var streak = 0
        while weeks.contains(week) { streak += 1; week = calendar.date(byAdding: .weekOfYear, value: -1, to: week)! }
        return streak
    }
    static func muscleVolume(_ sessions: [WorkoutSession]) -> [Muscle: Double] {
        var totals: [Muscle: Double] = [:]
        for entry in sessions.filter({ $0.status == .completed }).flatMap(\.entries) {
            let muscles = Set(entry.exercise.muscles)
            guard !muscles.isEmpty else { continue }
            let volume = qualifying(entry).reduce(0) { $0 + $1.loadKG * Double($1.reps) } / Double(muscles.count)
            for muscle in muscles { totals[muscle, default: 0] += volume }
        }
        return totals
    }
    static func dayLabel(_ date: Date, sessions: [WorkoutSession], routine: Routine?, now: Date = .now, calendar: Calendar = .current) -> String {
        let sameDay = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
        if sameDay.contains(where: { $0.status == .completed }) { return "Completed" }
        if sameDay.contains(where: { $0.status == .skipped }) { return "Skipped" }
        if sameDay.contains(where: { $0.status == .abandoned }) { return "Abandoned" }
        if sameDay.contains(where: \.isActive) { return "In progress" }
        // Do not rewrite the past using today's routine configuration.
        guard date >= calendar.startOfDay(for: now), let routine, let day = RoutineSchedule.day(in: routine, at: date, calendar: calendar) else { return "No log" }
        return day.kind == .rest ? "Rest" : day.kind == .workout ? "Planned" : "Flexible"
    }
    static func csv(_ sessions: [WorkoutSession]) -> String {
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["session_id,date,status,workout,exercise,set_type,reps,load_kg,seconds,distance_m,completed"]
        for session in sessions {
            for entry in session.entries {
                for set in entry.sets {
                    lines.append([session.id.uuidString, session.startedAt.ISO8601Format(), session.status.rawValue, quoted(session.title), quoted(entry.exercise.name), set.type.rawValue, String(set.reps), String(set.loadKG), String(set.seconds), String(set.distanceMeters), set.completedAt == nil ? "false" : "true"].joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

import Foundation

enum TodayWorkoutState: Equatable {
    case noRoutine
    case rest
    case flexible
    case planned(title: String, exerciseCount: Int, minutes: Int?)
    case completed(title: String, sets: Int, seconds: Double, volumeKG: Double)
}
struct HomeWorkoutInput {
    var hasRoutine = false
    var isRestDay = false
    var plannedTitle: String?
    var exerciseCount = 0
    var minutes: Int?
    var completion: (title: String, sets: Int, seconds: Double, volumeKG: Double)?
}
enum HomeStateResolver {
    /// Assign sessions by start date, matching the other weekly dashboard totals.
    static func weeklyWorkoutTime(_ sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current) -> HealthMetricSeries {
        var seconds = Array(repeating: 0.0, count: 7)
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return HealthMetricSeries(total: 0, buckets: seconds) }
        for session in sessions where session.status == .completed || session.isActive {
            guard session.startedAt >= week.start, session.startedAt < week.end, session.startedAt <= now,
                  session.isActive || (session.endedAt.map { $0 >= session.startedAt && $0 <= now } ?? false),
                  let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: week.start), to: calendar.startOfDay(for: session.startedAt)).day,
                  seconds.indices.contains(day) else { continue }
            let duration = session.duration(at: now)
            if duration.isFinite { seconds[day] += max(0, duration) }
        }
        return HealthMetricSeries(total: seconds.reduce(0, +) / 3600, buckets: seconds)
    }

    static func workout(_ input: HomeWorkoutInput) -> TodayWorkoutState {
        if !input.hasRoutine { return .noRoutine }
        if let c = input.completion { return .completed(title: c.title, sets: c.sets, seconds: c.seconds, volumeKG: c.volumeKG) }
        if input.isRestDay { return .rest }
        if let title = input.plannedTitle { return .planned(title: title, exerciseCount: input.exerciseCount, minutes: input.minutes) }
        return .flexible
    }
}

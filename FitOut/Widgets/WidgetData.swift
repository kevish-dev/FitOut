import Foundation

enum FitOutWidgetID {
    static let appGroup = "group.com.kevishsewliya.fitout"
    static let kinds = ["FitOut.Water", "FitOut.Workout", "FitOut.Steps", "FitOut.Calories", "FitOut.Sleep", "FitOut.Streak", "FitOut.Volume", "FitOut.Overview", "FitOut.Nutrition"]
}

enum WidgetDestination: String, CaseIterable, Identifiable {
    case home, water, workout, startWorkout, routine, health, analytics, history, nutrition
    var id: String { rawValue }
    var url: URL { URL(string: "fitout://widget/" + rawValue)! }
    init?(url: URL) {
        guard url.scheme?.lowercased() == "fitout", url.host == "widget", url.query == nil,
              url.fragment == nil, let value = Self(rawValue: String(url.path.dropFirst())) else { return nil }
        self = value
    }
}

struct WidgetGoals: Codable, Equatable, Sendable {
    var waterML: Double?
    var steps: Double?
    var activeCalories: Double?
    var sleepHours: Double?
    var isValid: Bool {
        [(waterML, 100.0...10_000), (steps, 100.0...100_000), (activeCalories, 50.0...10_000), (sleepHours, 1.0...24)]
            .allSatisfy { value, range in value == nil || (value!.isFinite && range.contains(value!)) }
    }
}

struct WidgetWaterLog: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let milliliters: Int
}

struct WidgetHealthReading: Codable, Equatable, Sendable {
    var measuredAt: Date?
    var waterML: Double?
    var steps: Double?
    var activeCalories: Double?
    var sleepHours: Double?
    var stepBuckets: [Double] = []
    var calorieBuckets: [Double] = []
    var sleepBuckets: [Double] = []
    func isCurrent(at date: Date, calendar: Calendar) -> Bool {
        measuredAt.map { $0 <= date && calendar.isDate($0, inSameDayAs: date) } ?? false
    }
}

struct WidgetWorkoutPlan: Codable, Equatable, Sendable {
    let date: Date
    let title: String
    let kind: String
    let exercises: [String]
    let exerciseCount: Int
    let minutes: Int?
}
struct WidgetActiveWorkout: Codable, Equatable, Sendable {
    let title: String
    let paused: Bool
    let completedSets: Int
    let totalSets: Int
    let restUntil: Date?
}
struct WidgetVolumeWeek: Codable, Equatable, Sendable {
    let date: Date
    let kilograms: Double
}
struct WidgetNutritionSnapshot: Codable, Equatable, Sendable {
    let date: Date
    let entryCount: Int
    let calories: Double?
    let protein: Double?
    let carbohydrates: Double?
    let fat: Double?
    let targetCalories: Double?
    let targetProtein: Double?
    let targetCarbohydrates: Double?
    let targetFat: Double?
    let incomplete: [String]
    let estimatedEntries: Int
}

/// Effective-dated rest rules are shared by the app and widget extension.
/// Weekdays use the routine's Monday=0 ... Sunday=6 convention.
struct StreakRestSchedule: Codable, Equatable, Sendable {
    let effectiveFrom: Date
    let validFrom: Date?
    let weekdays: Set<Int>
}

enum WorkoutDayStreak {
    static func isRestDay(_ date: Date, schedules: [StreakRestSchedule], calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard let schedule = schedules.filter({ calendar.startOfDay(for: $0.effectiveFrom) <= day })
            .max(by: { $0.effectiveFrom < $1.effectiveFrom }),
              schedule.validFrom.map({ day >= calendar.startOfDay(for: $0) }) ?? true else { return false }
        return schedule.weekdays.contains((calendar.component(.weekday, from: day) + 5) % 7)
    }

    static func count(completed: [Date], restSchedules: [StreakRestSchedule],
                      at now: Date, calendar: Calendar) -> Int {
        let days = Set(completed.filter { $0 <= now }.map { calendar.startOfDay(for: $0) })
        guard let earliest = days.min() else { return 0 }
        var cursor = calendar.startOfDay(for: now)
        // Today is still available to train; yesterday's missed training is not.
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while cursor >= earliest {
            if days.contains(cursor) { count += 1 }
            else if !isRestDay(cursor, schedules: restSchedules, calendar: calendar) { break }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

struct FitOutWidgetSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date?
    var onboarded = false
    var health = WidgetHealthReading()
    var plans: [WidgetWorkoutPlan] = []
    var hasRoutine = false
    var active: WidgetActiveWorkout?
    var completedDays: [Date] = []
    var volumeWeeks: [WidgetVolumeWeek] = []
    var weeklyWorkoutGoal = 0
    var usesPounds = false
    var nutrition: WidgetNutritionSnapshot?
    // Optional so caches written before rest-day protection still decode.
    var restSchedules: [StreakRestSchedule]?
}
struct FitOutWidgetState: Codable, Equatable, Sendable {
    var version = 1
    var snapshot = FitOutWidgetSnapshot()
    var water: [WidgetWaterLog] = []
    var goals = WidgetGoals()
    var waterDisplayUnit: String?

    func localWater(at date: Date, calendar: Calendar = .current) -> Int {
        water.filter { $0.date <= date && calendar.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.milliliters }
    }
    func totalWater(at date: Date, calendar: Calendar = .current) -> Double {
        let health = snapshot.health
        return Double(localWater(at: date, calendar: calendar)) + (health.isCurrent(at: date, calendar: calendar) ? health.waterML ?? 0 : 0)
    }
    func latestWater(at date: Date, calendar: Calendar = .current) -> WidgetWaterLog? {
        water.filter { $0.date <= date && calendar.isDate($0.date, inSameDayAs: date) }.max { $0.date < $1.date }
    }
    func plan(at date: Date, calendar: Calendar = .current) -> WidgetWorkoutPlan? {
        snapshot.plans.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
    func streak(at date: Date, calendar: Calendar = .current) -> Int {
        WorkoutDayStreak.count(completed: snapshot.completedDays, restSchedules: snapshot.restSchedules ?? [],
                              at: date, calendar: calendar)
    }
    func isRestDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        WorkoutDayStreak.isRestDay(date, schedules: snapshot.restSchedules ?? [], calendar: calendar)
    }
    func weekDays(at date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let sunday = calendar.date(byAdding: .day, value: 1 - calendar.component(.weekday, from: start), to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
    }
    func completed(on day: Date, through now: Date, calendar: Calendar = .current) -> Bool {
        snapshot.completedDays.contains { $0 <= now && calendar.isDate($0, inSameDayAs: day) }
    }
    func volume(at date: Date, offset: Int = 0, calendar: Calendar = .current) -> Double? {
        guard let shifted = calendar.date(byAdding: .weekOfYear, value: offset, to: date),
              let week = calendar.dateInterval(of: .weekOfYear, for: shifted) else { return nil }
        return snapshot.volumeWeeks.first { week.contains($0.date) }?.kilograms
    }
}

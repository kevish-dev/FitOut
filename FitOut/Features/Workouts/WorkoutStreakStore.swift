import Foundation
import Observation

struct WorkoutStreakCelebration: Identifiable {
    let id: String
    let day: Date
    let snapshot: DailyStreakSnapshot
    var previousCount: Int { max(0, snapshot.consecutiveDays - 1) }
}

/// Celebration state is separate from workout truth; deleting/undoing a session
/// always recalculates the streak rather than incrementing a saved counter.
@MainActor @Observable final class WorkoutStreakStore {
    static let storageKey = "fitout.streak.celebrations.v1"
    private struct Ledger: Codable {
        var acknowledged: Set<String> = []
        var pendingDay: String?
    }
    private(set) var pending: WorkoutStreakCelebration?
    @ObservationIgnored private var ledger: Ledger
    @ObservationIgnored private var previousSessions: [WorkoutSession]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults, sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current) {
        self.defaults = defaults; previousSessions = sessions
        ledger = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
        // Existing history establishes the baseline, never a burst of old popups.
        refreshPending(sessions: sessions, now: now, calendar: calendar)
    }
    func update(sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current) {
        let before = WorkoutAnalytics.dailyStreak(previousSessions, now: now, calendar: calendar)
        let after = WorkoutAnalytics.dailyStreak(sessions, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        func credited(_ snapshot: DailyStreakSnapshot) -> Bool { snapshot.weekDays.contains { $0.date == today && $0.isCompleted } }
        let key = Self.dayKey(today, calendar: calendar)
        if !credited(before), credited(after), after.consecutiveDays > before.consecutiveDays,
           !ledger.acknowledged.contains(key) { ledger.pendingDay = key }
        previousSessions = sessions
        refreshPending(sessions: sessions, now: now, calendar: calendar)
    }
    func acknowledge(_ id: String) {
        guard pending?.id == id else { return }
        ledger.acknowledged.insert(id); ledger.pendingDay = nil; pending = nil; persist()
    }
    private func refreshPending(sessions: [WorkoutSession], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now), key = Self.dayKey(now, calendar: calendar)
        let snapshot = WorkoutAnalytics.dailyStreak(sessions, now: now, calendar: calendar)
        guard ledger.pendingDay == key, !ledger.acknowledged.contains(key), snapshot.consecutiveDays > 0,
              snapshot.weekDays.contains(where: { $0.date == today && $0.isCompleted }) else {
            pending = nil; ledger.pendingDay = nil; persist(); return
        }
        pending = WorkoutStreakCelebration(id: key, day: today, snapshot: snapshot)
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: Self.storageKey) }
    }
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        var civil = Calendar(identifier: .gregorian); civil.timeZone = calendar.timeZone
        let parts = civil.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 1)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

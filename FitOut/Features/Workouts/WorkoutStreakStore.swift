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
    static let restStorageKey = "fitout.streak.restSchedules.v1"
    private struct Ledger: Codable {
        var acknowledged: Set<String> = []
        var pendingDay: String?
    }
    private(set) var pending: WorkoutStreakCelebration?
    private(set) var restSchedules: [StreakRestSchedule]
    @ObservationIgnored private var ledger: Ledger
    @ObservationIgnored private var previousSessions: [WorkoutSession]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults, sessions: [WorkoutSession], routine: Routine? = nil,
         now: Date = .now, calendar: Calendar = .current) {
        self.defaults = defaults; previousSessions = sessions
        ledger = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
        if let data = defaults.data(forKey: Self.restStorageKey),
           let saved = try? JSONDecoder().decode([StreakRestSchedule].self, from: data) {
            restSchedules = saved
        } else {
            // First upgrade can use the existing saved plan from its creation date.
            // Later schedule edits are recorded from today and never rewrite the past.
            let baseline = min(routine?.createdAt ?? now, now)
            restSchedules = [Self.schedule(routine, effectiveFrom: calendar.startOfDay(for: baseline))]
        }
        updateRoutine(routine, now: now, calendar: calendar)
        // Existing history establishes the baseline, never a burst of old popups.
        refreshPending(sessions: sessions, now: now, calendar: calendar)
    }
    func update(sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current) {
        let before = snapshot(sessions: previousSessions, now: now, calendar: calendar)
        let after = snapshot(sessions: sessions, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        func credited(_ snapshot: DailyStreakSnapshot) -> Bool { snapshot.weekDays.contains { $0.date == today && $0.isCompleted } }
        let key = Self.dayKey(today, calendar: calendar)
        if !credited(before), credited(after), after.consecutiveDays > before.consecutiveDays,
           !ledger.acknowledged.contains(key) { ledger.pendingDay = key }
        previousSessions = sessions
        refreshPending(sessions: sessions, now: now, calendar: calendar)
    }
    func snapshot(sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current) -> DailyStreakSnapshot {
        WorkoutAnalytics.dailyStreak(sessions, restSchedules: restSchedules, now: now, calendar: calendar)
    }
    func updateRoutine(_ routine: Routine?, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let proposal = Self.schedule(routine, effectiveFrom: today)
        let current = restSchedules.filter { calendar.startOfDay(for: $0.effectiveFrom) <= today }
            .max(by: { $0.effectiveFrom < $1.effectiveFrom })
        if current?.weekdays != proposal.weekdays || current?.validFrom != proposal.validFrom {
            restSchedules.removeAll { calendar.startOfDay(for: $0.effectiveFrom) == today }
            restSchedules.append(proposal)
            restSchedules.sort { $0.effectiveFrom < $1.effectiveFrom }
        }
        if let data = try? JSONEncoder().encode(restSchedules) { defaults.set(data, forKey: Self.restStorageKey) }
        // A schedule change preserves counts but never earns a celebration itself.
        refreshPending(sessions: previousSessions, now: now, calendar: calendar)
    }
    private static func schedule(_ routine: Routine?, effectiveFrom: Date) -> StreakRestSchedule {
        guard let routine, routine.isActive, routine.archivedAt == nil else {
            return StreakRestSchedule(effectiveFrom: effectiveFrom, validFrom: nil, weekdays: [])
        }
        return StreakRestSchedule(effectiveFrom: effectiveFrom, validFrom: max(routine.createdAt, routine.startsOn ?? routine.createdAt),
                                  weekdays: Set(routine.days.filter { $0.kind == .rest && (0..<7).contains($0.weekday) }.map(\.weekday)))
    }
    func acknowledge(_ id: String) {
        guard pending?.id == id else { return }
        ledger.acknowledged.insert(id); ledger.pendingDay = nil; pending = nil; persist()
    }
    private func refreshPending(sessions: [WorkoutSession], now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now), key = Self.dayKey(now, calendar: calendar)
        let snapshot = self.snapshot(sessions: sessions, now: now, calendar: calendar)
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

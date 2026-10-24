import Foundation

enum GymTodayState: Equatable {
    case setup
    case active(WorkoutSession)
    case scheduled(RoutineDay)
    case needsExercises(RoutineDay)
    case rest
    case unassigned
    case completed(WorkoutSession)
}

struct GymWeekDay: Identifiable {
    enum Status { case completed, active, planned, rest, unassigned, noLog, skipped, abandoned }
    let date: Date
    let weekday: Int
    let isToday: Bool
    let plan: RoutineDay?
    let session: WorkoutSession?
    let status: Status
    var id: Date { date }

    var title: String {
        if let session { return session.title }
        switch status {
        case .noLog: return "No workout logged"
        case .rest: return "Rest day"
        case .unassigned: return "Unassigned"
        default: return plan?.title ?? "Unassigned"
        }
    }

    var detail: String {
        switch status {
        case .completed: return "Completed"
        case .active: return "In progress"
        case .rest: return "Recovery"
        case .unassigned: return "Plan a day"
        case .noLog: return "View day plan"
        case .skipped: return "Skipped"
        case .abandoned: return "Ended early"
        case .planned:
            let count = plan?.exercises.count ?? 0
            return count == 0 ? "Add exercises" : "\(count) exercises"
        }
    }
}

/// Dates are injected so the landing page and its tests use the same calendar rules.
enum GymLandingState {
    static func today(routine: Routine?, sessions: [WorkoutSession], now: Date = .now,
                      calendar: Calendar = .current) -> GymTodayState {
        if let active = sessions.first(where: \.isActive) { return .active(active) }
        guard let routine, routine.days.contains(where: { $0.kind == .workout }) else { return .setup }
        guard routine.hasStarted(at: now, calendar: calendar) else { return .unassigned }
        let day = RoutineSchedule.day(in: routine, at: now, calendar: calendar)
        let completed = completedSessions(sessions, through: now).first {
            calendar.isDate($0.startedAt, inSameDayAs: now)
                && (day?.kind != .workout || $0.routineID == routine.id)
        }
        if let completed { return .completed(completed) }
        guard let day else { return .unassigned }
        switch day.kind {
        case .rest: return .rest
        case .flexible: return .unassigned
        case .workout: return day.exercises.isEmpty ? .needsExercises(day) : .scheduled(day)
        }
    }

    static func monday(containing date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -RoutineSchedule.weekday(for: day, calendar: calendar), to: day) ?? day
    }

    static func completedSessions(_ sessions: [WorkoutSession], through now: Date) -> [WorkoutSession] {
        sessions.filter {
            $0.status == .completed && $0.startedAt <= now && ($0.endedAt ?? $0.startedAt) <= now
        }.sorted { $0.startedAt > $1.startedAt }
    }

    static func week(routine: Routine?, sessions: [WorkoutSession], offset: Int = 0,
                     now: Date = .now, calendar: Calendar = .current) -> [GymWeekDay] {
        let start = calendar.date(byAdding: .weekOfYear, value: offset, to: monday(containing: now, calendar: calendar)) ?? now
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: start) else { return nil }
            let plan = routine.flatMap { $0.hasStarted(at: date, calendar: calendar) ? RoutineSchedule.day(in: $0, at: date, calendar: calendar) : nil }
            let logs = sessions.filter {
                $0.startedAt <= now && calendar.isDate($0.startedAt, inSameDayAs: date)
                    && ($0.isActive || ($0.endedAt ?? $0.startedAt) <= now)
            }.sorted { $0.startedAt > $1.startedAt }
            let session = logs.first(where: \.isActive) ?? logs.first(where: { $0.status == .completed }) ?? logs.first
            let status: GymWeekDay.Status
            if let session {
                switch session.status {
                case .inProgress, .paused: status = .active
                case .completed: status = .completed
                case .skipped: status = .skipped
                case .abandoned: status = .abandoned
                }
            } else if date < calendar.startOfDay(for: now) {
                // A repeating plan describes the current schedule, not historical attendance.
                status = .noLog
            } else {
                switch plan?.kind {
                case .workout: status = .planned
                case .rest: status = .rest
                default: status = .unassigned
                }
            }
            return GymWeekDay(date: date, weekday: index, isToday: calendar.isDate(date, inSameDayAs: now),
                              plan: plan, session: session, status: status)
        }
    }

    static func completedThisWeek(_ sessions: [WorkoutSession], now: Date = .now,
                                  calendar: Calendar = .current) -> [WorkoutSession] {
        let start = monday(containing: now, calendar: calendar)
        return completedSessions(sessions, through: now).filter { $0.startedAt >= start }
    }
}

/// One presentation slot prevents competing workout/plan/summary sheets.
enum GymDestination: Identifiable {
    case workout
    case routine(Routine, weekday: Int?, stage: RoutineEditorStage?)
    case create(weekday: Int?, useAsActive: Bool)
    case summary(WorkoutSession)
    var id: String {
        switch self {
        case .workout: return "workout"
        case let .routine(routine, weekday, stage): return "routine-\(routine.id)-\(weekday ?? -1)-\(stage?.rawValue ?? "resume")"
        case let .create(weekday, active): return "create-\(weekday ?? -1)-\(active)"
        case let .summary(session): return "summary-\(session.id)"
        }
    }
}
struct GymNavigation {
    private(set) var destination: GymDestination?
    @discardableResult mutating func present(_ value: GymDestination) -> Bool {
        guard destination == nil else { return false }
        destination = value; return true
    }
    mutating func dismiss() { destination = nil }
    static func plan(active: Routine?, draft: RoutineDraft?, weekday: Int? = nil, weekly: Bool = false) -> GymDestination {
        if let routine = active ?? draft?.routine {
            return .routine(routine, weekday: weekday, stage: weekly ? .schedule : nil)
        }
        return .create(weekday: weekday, useAsActive: true)
    }
}

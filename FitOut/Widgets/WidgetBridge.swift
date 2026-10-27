import Foundation
import Observation
import WidgetKit

@MainActor @Observable final class HydrationStore {
    private let shared: WidgetSharedStore?
    private(set) var state = FitOutWidgetState()
    var error: String?
    var onFeedback: ((FitHapticEvent) -> Void)?
    var waterDisplayUnit: String { state.waterDisplayUnit == "L" ? "L" : "ml" }
    init(shared: WidgetSharedStore?, fallback: WidgetSharedStore? = nil) { self.shared = shared ?? fallback; refresh() }
    func refresh() {
        guard let shared else { return }
        do { state = try shared.read(); error = nil } catch { self.error = error.localizedDescription }
    }
    func log(_ amount: Int, at date: Date = .now) { change(feedback: .saved) { try $0.logWater(amount, at: date) } }
    func remove(_ id: UUID) { change(feedback: .saved) { try $0.removeWater(id: id) } }
    func edit(_ id: UUID, amount: Int, date: Date) { change(feedback: .saved) { try $0.editWater(id: id, milliliters: amount, date: date) } }
    func displayUnit(_ unit: String) { guard ["ml", "L"].contains(unit) else { return }; change(feedback: .selection) { try $0.update { $0.waterDisplayUnit = unit } } }
    @discardableResult func clearHistory() -> Bool { change(feedback: .saved) { try $0.update { $0.water = [] } } }
    func publishSnapshot(_ snapshot: FitOutWidgetSnapshot) { change { try $0.update { $0.snapshot = snapshot } } }
    @discardableResult func saveGoals(_ goals: WidgetGoals) -> Bool { change(feedback: .saved) { try $0.saveGoals(goals) } }
    @discardableResult private func change(feedback: FitHapticEvent? = nil, _ action: (WidgetSharedStore) throws -> FitOutWidgetState) -> Bool {
        do {
            guard let shared else { throw WidgetStoreError.appGroupUnavailable }
            state = try action(shared)
            error = nil
            WidgetCenter.shared.reloadAllTimelines()
            if let feedback { onFeedback?(feedback) }
            return true
        } catch { self.error = error.localizedDescription; if feedback != nil { onFeedback?(.warning) }; return false }
    }
}

@MainActor final class WidgetBridge {
    private let shared: WidgetSharedStore?
    private let gym: GymStore
    private let workouts: WorkoutStore
    private let health: HealthAccessService
    private let profile: ProfileStore
    private let hydration: HydrationStore
    private let nutrition: NutritionStore
    private let streaks: WorkoutStreakStore
    init(shared: WidgetSharedStore?, gym: GymStore, workouts: WorkoutStore, health: HealthAccessService, profile: ProfileStore, hydration: HydrationStore, nutrition: NutritionStore, streaks: WorkoutStreakStore) {
        self.shared = shared; self.gym = gym; self.workouts = workouts; self.health = health; self.profile = profile; self.hydration = hydration
        self.nutrition = nutrition
        self.streaks = streaks
        gym.onChange = { [weak self] in self?.publish() }
        workouts.onChange = { [weak self] in self?.publish() }
        health.onChange = { [weak self] in self?.publish() }
        profile.onChange = { [weak self] in self?.publish() }
        nutrition.onChange = { [weak self] in self?.publish() }
        publish()
    }
    func publish(at now: Date = .now, calendar: Calendar = .current) {
        streaks.updateRoutine(gym.activeRoutine, now: now, calendar: calendar)
        var snapshot = FitOutWidgetSnapshot()
        snapshot.restSchedules = streaks.restSchedules
        snapshot.updatedAt = now
        snapshot.onboarded = profile.draft.completedAt != nil
        snapshot.usesPounds = profile.draft.weightUnit == .lbs
        let summary = nutrition.summary(on: now, calendar: calendar)
        let values = summary.values
        let goals = nutrition.target(on: now, calendar: calendar)
        snapshot.nutrition = WidgetNutritionSnapshot(date: now, entryCount: summary.entries.count,
            calories: values.calories, protein: values.protein, carbohydrates: values.carbohydrates, fat: values.fat,
            targetCalories: goals.calories, targetProtein: goals.protein, targetCarbohydrates: goals.carbohydrates, targetFat: goals.fat,
            incomplete: summary.entries.isEmpty ? [] : NutritionNutrient.allCases.filter { !summary.isComplete($0) }.map(\.rawValue), estimatedEntries: summary.estimateCount)
        snapshot.health = WidgetHealthReading(measuredAt: health.lastRefreshedAt, waterML: health.overview.waterMilliliters.total,
                                             steps: health.overview.steps.total, activeCalories: health.overview.activeCalories.total,
                                             sleepHours: health.overview.sleepHours.total, stepBuckets: health.overview.steps.buckets,
                                             calorieBuckets: health.overview.activeCalories.buckets, sleepBuckets: health.overview.sleepHours.buckets)
        if let active = workouts.active {
            snapshot.active = WidgetActiveWorkout(title: active.title, paused: active.status == .paused,
                completedSets: active.completedSets.count, totalSets: active.entries.filter { !$0.skipped }.flatMap(\.sets).count, restUntil: active.restUntil)
        }
        let completed = workouts.history.filter { $0.status == .completed && $0.startedAt <= ($0.endedAt ?? $0.startedAt) && ($0.endedAt ?? $0.startedAt) <= now }
        snapshot.completedDays = Array(Set(completed.map { $0.endedAt ?? $0.startedAt })).sorted()
        snapshot.volumeWeeks = WorkoutAnalytics.recentWeeklyVolume(workouts.history, now: now, calendar: calendar).weeks.map {
            WidgetVolumeWeek(date: $0.start, kilograms: $0.volumeKG)
        }
        if let routine = gym.activeRoutine {
            snapshot.hasRoutine = !routine.trainingDays.isEmpty
            snapshot.weeklyWorkoutGoal = routine.trainingDays.count
            snapshot.plans = (0..<8).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      routine.hasStarted(at: date, calendar: calendar), let day = RoutineSchedule.day(in: routine, at: date, calendar: calendar) else { return nil }
                return WidgetWorkoutPlan(date: date, title: day.title.isEmpty ? day.kind.rawValue : day.title, kind: day.kind.rawValue,
                    exercises: day.exercises.prefix(6).compactMap { gym.exercise($0.exerciseID)?.name }, exerciseCount: day.exercises.count, minutes: day.durationMinutes)
            }
        }
        guard let shared else { hydration.publishSnapshot(snapshot); return }
        do {
            try shared.update { $0.snapshot = snapshot }
            hydration.refresh()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { hydration.error = error.localizedDescription }
    }
}

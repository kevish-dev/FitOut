import Foundation
import SwiftData
import Observation

@MainActor final class AppContainer {
    let defaults: UserDefaults
    let workouts: WorkoutStore
    let gym: GymStore
    let nutrition: NutritionStore
    let health: HealthAccessService
    let coach: CoachStore
    let hydration: HydrationStore
    let widgets: WidgetBridge
    let workoutPresentation: WorkoutPresentationCoordinator
    let streaks: WorkoutStreakStore
    let streakPresentation: WorkoutStreakPresenter
    let hydrationReminders: HydrationReminderStore
    let database: ModelContainer
    let repository: SwiftDataRepository
    let presentation: AppPresentationPreferences
    let profile: ProfileStore
    let capabilities: any RuntimeCapabilityProviding
    let haptics: HapticService
    let workoutHaptics: WorkoutHapticCoordinator

    init(database: ModelContainer, capabilities: any RuntimeCapabilityProviding = SystemCapabilityProvider(), legacyDefaults: UserDefaults? = nil, defaults: UserDefaults = .standard) throws {
        workouts = try WorkoutStore(container: database)
        gym = try GymStore(container: database)
        nutrition = try NutritionStore(container: database)
        self.defaults = defaults
        health = HealthAccessService(capability: capabilities, defaults: defaults)
        self.database = database
        repository = SwiftDataRepository(container: database)
        let realFeedback = defaults === UserDefaults.standard && !database.configurations.allSatisfy(\.isStoredInMemoryOnly)
        haptics = HapticService(defaults: defaults, repository: repository, playbackEnabled: realFeedback)
        workoutHaptics = WorkoutHapticCoordinator(store: workouts, haptics: haptics, enabled: realFeedback)
        presentation = try AppPresentationPreferences(repository: repository, defaults: defaults)
        self.capabilities = capabilities
        if let legacyDefaults { try LegacyOnboardingImporter.importIfNeeded(from: legacyDefaults, into: repository) }
        profile = try ProfileStore(container: database, legacy: repository.loadSnapshot())
        // UI-test suites and injected test defaults never write production widget data.
        let shared = defaults === UserDefaults.standard ? try? WidgetSharedStore.live() : nil
        let production = defaults === UserDefaults.standard
        let localRoot: URL
        if production {
            localRoot = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("FitOut/Hydration", isDirectory: true)
        } else {
            let key = "hydration.test.storageID"
            let identifier = defaults.string(forKey: key) ?? UUID().uuidString
            defaults.set(identifier, forKey: key)
            localRoot = FileManager.default.temporaryDirectory.appendingPathComponent("FitOutHydrationTests/" + identifier, isDirectory: true)
        }
        let fallback = WidgetSharedStore(directory: localRoot)
        if let shared, production {
            // Import fallback logs only once per ID if App Groups become available later.
            let local = try fallback.read()
            let imported = Set(defaults.stringArray(forKey: "hydration.widgetImportedIDs") ?? [])
            let pending = local.water.filter { !imported.contains($0.id.uuidString) }
            if !pending.isEmpty {
                try shared.update { state in
                    let known = Set(state.water.map(\.id)); state.water += pending.filter { !known.contains($0.id) }
                    if state.goals.waterML == nil { state.goals.waterML = local.goals.waterML }
                    if state.waterDisplayUnit == nil { state.waterDisplayUnit = local.waterDisplayUnit }
                }
                defaults.set(Array(imported.union(pending.map { $0.id.uuidString })), forKey: "hydration.widgetImportedIDs")
                try fallback.update { $0.water = [] }
            }
        }
        hydration = HydrationStore(shared: shared, fallback: fallback)
        let coachRoot = (production ? localRoot.deletingLastPathComponent() : localRoot).appendingPathComponent("Coach", isDirectory: true)
        let coachPersistence: any CoachPersisting = database.configurations.allSatisfy(\.isStoredInMemoryOnly)
            ? MemoryCoachPersistence() : FileCoachPersistence(url: coachRoot.appendingPathComponent("conversations.json"))
        coach = CoachStore(capabilities: capabilities, persistence: coachPersistence)
        hydrationReminders = HydrationReminderStore(defaults: defaults)
        streaks = WorkoutStreakStore(defaults: defaults, sessions: workouts.sessions, routine: gym.activeRoutine)
        widgets = WidgetBridge(shared: shared, gym: gym, workouts: workouts, health: health, profile: profile, hydration: hydration, nutrition: nutrition, streaks: streaks)
        workoutPresentation = WorkoutPresentationCoordinator(store: workouts, gym: gym, profile: profile, defaults: defaults,
            enabled: production && !database.configurations.allSatisfy(\.isStoredInMemoryOnly), haptics: haptics)
        streakPresentation = WorkoutStreakPresenter(store: streaks, enabled: production && !database.configurations.allSatisfy(\.isStoredInMemoryOnly),
            preferences: { [weak repository] in (try? repository?.loadPreferences()) ?? AppPreferences() }, haptics: haptics)
        workouts.onMutation = { [weak workoutHaptics] before, after, date in workoutHaptics?.saved(before: before, after: after, at: date) }
        haptics.onSettingsChange = { [weak workoutHaptics] in workoutHaptics?.settingsChanged() }
        gym.onFeedback = { [weak haptics] event in haptics?.play(event) }
        nutrition.onFeedback = { [weak haptics] event in haptics?.play(event) }
        hydration.onFeedback = { [weak haptics] event in haptics?.play(event) }
        profile.onFeedback = { [weak haptics] event in haptics?.play(event) }
        coach.onFeedback = { [weak haptics] event in haptics?.play(event) }
        workouts.onChange = { [weak widgets, weak workoutPresentation, weak streaks, weak streakPresentation, weak workouts] in
            widgets?.publish(); workoutPresentation?.changed()
            if let workouts { streaks?.update(sessions: workouts.sessions) }
            streakPresentation?.refresh()
        }
        workouts.onEditorVisibilityChange = { [weak workoutPresentation] in workoutPresentation?.overlayChanged() }
        presentation.onChange = { [weak presentation, weak workoutPresentation] in workoutPresentation?.appearanceChanged(presentation?.appearance.colorScheme) }
        workoutPresentation.appearanceChanged(presentation.appearance.colorScheme)
    }

    static func live() throws -> AppContainer {
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-test-session"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let id = ProcessInfo.processInfo.arguments[index + 1]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("SessionUITests-" + id).appendingPathComponent("store")
            let defaults = UserDefaults(suiteName: "session-ui-" + id)!
            defaults.set(true, forKey: "health.explainer.seen")
            let container = try AppContainer(database: PersistenceFactory.makeContainer(at: url), defaults: defaults)
            if container.profile.draft.completedAt == nil { container.profile.draft.name = "UITest"; container.profile.draft.primaryGoal = .fitness; _ = container.profile.complete() }
            return container
        }
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--ui-test-profile"), ProcessInfo.processInfo.arguments.count > index + 1 {
            let id = ProcessInfo.processInfo.arguments[index + 1]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ProfileUITests-" + id).appendingPathComponent("store")
            return try AppContainer(database: PersistenceFactory.makeContainer(at: url), defaults: UserDefaults(suiteName: "uitest-" + id)!)
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-shell") {
            let provider = FixedCapabilityProvider(snapshot: CapabilitySnapshot(healthKit: .unavailable(.systemUnavailable), foundationModels: .unavailable(.systemUnavailable), imagePlayground: .unavailable(.systemUnavailable)))
            let container = try AppContainer(database: PersistenceFactory.makeContainer(inMemory: true), capabilities: provider, defaults: UserDefaults(suiteName: "uitest-shell-" + UUID().uuidString)!)
            container.profile.draft.name = "UITest"
            container.profile.draft.primaryGoal = .fitness
            _ = container.profile.complete()
            return container
        }
        #endif
        return try AppContainer(database: PersistenceFactory.makeContainer(), legacyDefaults: .standard)
    }
}

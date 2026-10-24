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
    let hydrationReminders: HydrationReminderStore
    let database: ModelContainer
    let repository: SwiftDataRepository
    let profile: ProfileStore
    let capabilities: any RuntimeCapabilityProviding

    init(database: ModelContainer, capabilities: any RuntimeCapabilityProviding = SystemCapabilityProvider(), legacyDefaults: UserDefaults? = nil, defaults: UserDefaults = .standard) throws {
        workouts = try WorkoutStore(container: database)
        gym = try GymStore(container: database)
        nutrition = try NutritionStore(container: database)
        self.defaults = defaults
        health = HealthAccessService(capability: capabilities, defaults: defaults)
        coach = CoachStore(capabilities: capabilities)
        self.database = database
        repository = SwiftDataRepository(container: database)
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
        hydrationReminders = HydrationReminderStore(defaults: defaults)
        widgets = WidgetBridge(shared: shared, gym: gym, workouts: workouts, health: health, profile: profile, hydration: hydration, nutrition: nutrition)
        workoutPresentation = WorkoutPresentationCoordinator(store: workouts, gym: gym, profile: profile, defaults: defaults,
            enabled: production && !database.configurations.allSatisfy(\.isStoredInMemoryOnly))
        workouts.onChange = { [weak widgets, weak workoutPresentation] in widgets?.publish(); workoutPresentation?.changed() }
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

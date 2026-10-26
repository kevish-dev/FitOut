import XCTest
@testable import FitOut

final class HapticTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    func testEveryCueHasValidDefaultsAndPulseShape() {
        let settings = FitHapticSettings()
        XCTAssertTrue(settings.isValid)
        for event in FitHapticEvent.allCases {
            let pulses = HapticPatternPolicy.pulses(for: event, settings: settings)
            XCTAssertEqual(pulses.count, event.defaults.pulses)
            XCTAssertEqual(pulses.first?.time, 0)
            XCTAssertTrue(pulses.allSatisfy { $0.intensity > 0 && $0.intensity <= 1 && $0.time >= 0 })
        }
    }
    func testMasterZeroAndIndividualOffAlwaysProduceSilence() {
        var settings = FitHapticSettings(); settings.enabled = false
        for event in FitHapticEvent.allCases { XCTAssertTrue(HapticPatternPolicy.pulses(for: event, settings: settings).isEmpty) }
        settings.enabled = true; settings.strength = 0
        XCTAssertTrue(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).isEmpty)
        settings.strength = 1
        var cue = settings.cue(.restEnded); cue.enabled = false; settings.cues[.restEnded] = cue
        XCTAssertTrue(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).isEmpty)
        cue.enabled = true; cue.intensity = 0; settings.cues[.restEnded] = cue
        XCTAssertTrue(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).isEmpty)
    }
    func testConfiguredIntensityPulseCountSpacingAndFeelAreExactAndInvalidValuesAreRejected() {
        var settings = FitHapticSettings(); settings.strength = 0.5
        settings.cues[.restEnded] = HapticCueSettings(intensity: 0.8, pulses: 5, spacing: 0.3, feel: .soft)
        let pulses = HapticPatternPolicy.pulses(for: .restEnded, settings: settings)
        XCTAssertEqual(pulses.count, 5)
        XCTAssertEqual(pulses[4].time, 1.2, accuracy: 0.0001)
        XCTAssertEqual(pulses[0].intensity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(pulses[0].sharpness, HapticFeel.soft.sharpness)
        for cue in [HapticCueSettings(intensity: .nan, pulses: 1), HapticCueSettings(intensity: 1, pulses: 6), HapticCueSettings(intensity: 1, pulses: 0), HapticCueSettings(intensity: 1, pulses: 1, spacing: 0.01)] {
            settings.cues[.restEnded] = cue
            XCTAssertFalse(settings.isValid)
            XCTAssertTrue(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).isEmpty)
        }
    }
    @MainActor func testSettingsRelaunchKeepsAllCuesAndHonorsTheExistingMasterPreference() throws {
        let defaults = UserDefaults(suiteName: "haptics-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let repo = HapticPreferencesStub(); repo.preferences.appearance = .light; repo.preferences.hapticsEnabled = false
        let service = HapticService(defaults: defaults, repository: repo, output: HapticOutputStub())
        XCTAssertFalse(service.settings.enabled)
        var next = service.settings; next.enabled = true; next.strength = 0.4
        next.cues[.restEnded] = HapticCueSettings(intensity: 0.5, pulses: 4, spacing: 0.4, feel: .crisp)
        XCTAssertTrue(service.update(next))
        let restored = HapticService(defaults: defaults, repository: repo, output: HapticOutputStub())
        XCTAssertEqual(restored.settings, next)
        XCTAssertEqual(repo.preferences.appearance, .light)
        XCTAssertTrue(repo.preferences.hapticsEnabled)
    }
    @MainActor func testLegacyDisabledFlagMigratesAndFailedSaveKeepsOldSettings() {
        let defaults = UserDefaults(suiteName: "haptics-legacy-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey); defaults.removeObject(forKey: "haptics.disabled") }
        defaults.set(true, forKey: "haptics.disabled")
        let repo = HapticPreferencesStub(), output = HapticOutputStub()
        let service = HapticService(defaults: defaults, repository: repo, output: output)
        XCTAssertFalse(service.settings.enabled)
        repo.failSave = true
        var next = service.settings; next.enabled = true
        XCTAssertFalse(service.update(next))
        XCTAssertFalse(service.settings.enabled)
        XCTAssertTrue(defaults.bool(forKey: "haptics.disabled"))
        XCTAssertNotNil(service.error)
        repo.failSave = false
        XCTAssertTrue(service.update(next))
        XCTAssertNil(defaults.object(forKey: "haptics.disabled"))
    }
    @MainActor func testInactiveAndDisabledPlaybackCannotVibrateIncludingPreview() {
        let defaults = UserDefaults(suiteName: "haptics-active-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let output = HapticOutputStub(), repo = HapticPreferencesStub()
        let service = HapticService(defaults: defaults, repository: repo, output: output)
        service.play(.restEnded)
        XCTAssertTrue(output.patterns.isEmpty)
        service.sceneChanged(active: true); service.play(.restEnded)
        XCTAssertEqual(output.patterns.count, 1)
        service.setEnabled(false)
        service.play(.workoutCompleted); service.preview(.restEnded, cue: FitHapticEvent.restEnded.defaults)
        XCTAssertEqual(output.patterns.count, 1)
        XCTAssertGreaterThan(output.stops, 0)
    }
    @MainActor func testRateLimitingAndAlertPriorityPreventSelectionOrChatFromMaskingRestCue() {
        let defaults = UserDefaults(suiteName: "haptics-priority-" + UUID().uuidString)!
        let output = HapticOutputStub()
        let service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: output)
        service.sceneChanged(active: true)
        service.play(.selection, now: time); service.play(.selection, now: time.addingTimeInterval(0.02))
        XCTAssertEqual(output.patterns.count, 1)
        service.play(.restEnded, now: time.addingTimeInterval(0.1))
        service.play(.selection, now: time.addingTimeInterval(0.2))
        service.play(.coachReply, now: time.addingTimeInterval(0.2))
        XCTAssertEqual(output.patterns.count, 2)
        service.play(.selection, now: time.addingTimeInterval(2))
        XCTAssertEqual(output.patterns.count, 3)
        service.sceneChanged(active: false)
        service.play(.restEnded, now: time.addingTimeInterval(3))
        XCTAssertEqual(output.patterns.count, 3)
    }
    func testWorkoutEventsPreferFinalCompletionAndDoNotBuzzForEditsOrEarlyRestSkip() {
        var before = WorkoutSession(title: "Training", startedAt: time, entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(), WorkoutSet()])], execution: WorkoutExecution(phase: .activeSet))
        var after = before; after.notes = "Changed note"
        XCTAssertNil(WorkoutHapticPolicy.event(before: before, after: after, now: time))
        after.entries[0].sets[0].completedAt = time
        XCTAssertEqual(WorkoutHapticPolicy.event(before: before, after: after, now: time), .setCompleted)
        after.status = .completed
        XCTAssertEqual(WorkoutHapticPolicy.event(before: before, after: after, now: time), .workoutCompleted)
        before.restUntil = time.addingTimeInterval(10); before.execution?.phase = .resting
        after = before; after.restUntil = nil; after.execution?.phase = .ready
        XCTAssertEqual(WorkoutHapticPolicy.event(before: before, after: after, now: time), .selection)
        XCTAssertEqual(WorkoutHapticPolicy.event(before: before, after: after, now: time.addingTimeInterval(10)), .restEnded)
        XCTAssertNil(WorkoutHapticPolicy.event(before: after, after: after, now: time.addingTimeInterval(10)))
        after.execution?.phase = .activeSet
        XCTAssertEqual(WorkoutHapticPolicy.event(before: WorkoutSession(title: "Next", execution: WorkoutExecution(phase: .exerciseTransition)), after: after, now: time), .workoutStarted)
        before = after; before.execution?.phase = .exerciseTransition
        XCTAssertEqual(WorkoutHapticPolicy.event(before: before, after: after, now: time), .nextExercise)
    }
    func testRestAlertRequiresExplicitPreferenceActiveRestAndAFutureDeadline() {
        var session = WorkoutSession(title: "Training", restUntil: time.addingTimeInterval(20), entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet()])], execution: WorkoutExecution(phase: .resting))
        var settings = FitHapticSettings()
        XCTAssertNil(WorkoutRestAlert.make(session: session, settings: settings, now: time))
        settings.backgroundRestAlerts = true
        XCTAssertNotNil(WorkoutRestAlert.make(session: session, settings: settings, now: time))
        session.status = .paused
        XCTAssertNil(WorkoutRestAlert.make(session: session, settings: settings, now: time))
        session.status = .inProgress
        XCTAssertNil(WorkoutRestAlert.make(session: session, settings: settings, now: time.addingTimeInterval(21)))
        settings.enabled = false
        XCTAssertNil(WorkoutRestAlert.make(session: session, settings: settings, now: time))
    }

    @MainActor func testRestTimerAdvancesAndSignalsOnceEvenWithoutAWorkoutEditor() async throws {
        let defaults = UserDefaults(suiteName: "haptics-timer-" + UUID().uuidString)!
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let output = HapticOutputStub(), alerts = RestAlertStub()
        let service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: output)
        let coordinator = WorkoutHapticCoordinator(store: store, haptics: service, alerts: alerts)
        store.onMutation = { [weak coordinator] before, after, date in coordinator?.saved(before: before, after: after, at: date) }
        coordinator.sceneChanged(active: true)
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(restSeconds: 1), WorkoutSet(restSeconds: 1)])])
        XCTAssertTrue(store.startQuickWorkout(draft, unit: .kg))
        let id = try XCTUnwrap(store.active?.id)
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: id))
        XCTAssertEqual(store.active?.execution?.phase, .resting)
        try await Task.sleep(for: .milliseconds(1_200))
        XCTAssertEqual(store.active?.execution?.phase, .ready)
        XCTAssertNil(store.active?.restUntil)
        XCTAssertEqual(output.patterns.last?.count, 3)
        let played = output.patterns.count
        XCTAssertTrue(store.prepareFocusedSession(id))
        XCTAssertEqual(output.patterns.count, played)
        XCTAssertEqual(store.visibleEditorCount, 0)
        coordinator.sceneChanged(active: false); await coordinator.flushAlerts()
    }
    @MainActor func testAlertsReplaceOnExtensionCancelOnPauseAndMasterOffAndNeverRequestPermissionAutomatically() async throws {
        let defaults = UserDefaults(suiteName: "haptics-alert-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: HapticOutputStub())
        let alerts = RestAlertStub(), coordinator = WorkoutHapticCoordinator(store: store, haptics: service, alerts: alerts)
        service.onSettingsChange = { [weak coordinator] in coordinator?.settingsChanged() }
        store.onMutation = { [weak coordinator] before, after, date in coordinator?.saved(before: before, after: after, at: date) }
        coordinator.sceneChanged(active: true)
        XCTAssertEqual(alerts.requests, 0)
        await coordinator.setBackgroundAlerts(true)
        XCTAssertEqual(alerts.requests, 1)
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(restSeconds: 90), WorkoutSet()])])
        XCTAssertTrue(store.startQuickWorkout(draft, unit: .kg))
        let id = try XCTUnwrap(store.active?.id)
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: id)); await coordinator.flushAlerts()
        let original = try XCTUnwrap(alerts.current?.deadline)
        XCTAssertTrue(store.performFocused(.extendRest, sessionID: id)); await coordinator.flushAlerts()
        XCTAssertEqual(try XCTUnwrap(alerts.current?.deadline), original.addingTimeInterval(15))
        store.pause(); await coordinator.flushAlerts(); XCTAssertNil(alerts.current)
        store.resume(); await coordinator.flushAlerts(); XCTAssertNotNil(alerts.current)
        service.setEnabled(false); await coordinator.flushAlerts(); XCTAssertNil(alerts.current)
        XCTAssertEqual(alerts.requests, 1)
        coordinator.sceneChanged(active: false); await coordinator.flushAlerts()
    }
    @MainActor func testBackgroundRecoveryDoesNotReplayExpiredHapticAndPermissionDenialIsHonest() async throws {
        let defaults = UserDefaults(suiteName: "haptics-recovery-" + UUID().uuidString)!
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let output = HapticOutputStub(), alerts = RestAlertStub(); alerts.authorized = false
        let service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: output)
        var now = time
        let coordinator = WorkoutHapticCoordinator(store: store, haptics: service, alerts: alerts, clock: { now })
        store.onMutation = { [weak coordinator] before, after, date in coordinator?.saved(before: before, after: after, at: date) }
        coordinator.sceneChanged(active: true)
        await coordinator.setBackgroundAlerts(true)
        XCTAssertFalse(service.settings.backgroundRestAlerts); XCTAssertNotNil(coordinator.error)
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(restSeconds: 30), WorkoutSet()])])
        XCTAssertTrue(store.startQuickWorkout(draft, unit: .kg, now: now))
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: try XCTUnwrap(store.active?.id), now: now))
        coordinator.sceneChanged(active: false)
        let count = output.patterns.count
        now = now.addingTimeInterval(60)
        coordinator.sceneChanged(active: true)
        XCTAssertEqual(store.active?.execution?.phase, .ready)
        XCTAssertEqual(output.patterns.count, count)
        coordinator.sceneChanged(active: false); await coordinator.flushAlerts()
    }
}

@MainActor private final class HapticPreferencesStub: PreferencesRepository {
    var preferences = AppPreferences()
    var failSave = false
    func loadPreferences() throws -> AppPreferences { preferences }
    func savePreferences(_ preferences: AppPreferences) throws { if failSave { throw CocoaError(.fileWriteOutOfSpace) }; self.preferences = preferences }
}
@MainActor private final class HapticOutputStub: HapticPlaying {
    let supported = true
    var patterns: [[HapticPulse]] = []
    var stops = 0
    func play(_ pulses: [HapticPulse]) { patterns.append(pulses) }
    func stop() { stops += 1 }
}
@MainActor private final class RestAlertStub: WorkoutRestAlertScheduling {
    var current: WorkoutRestAlert?
    var requests = 0
    var authorized = true
    func replace(_ alert: WorkoutRestAlert?) async throws { current = alert }
    func requestAccess() async throws -> Bool { requests += 1; return authorized }
    func isAuthorized() async -> Bool { authorized }
}

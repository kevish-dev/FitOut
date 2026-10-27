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
        for cue in [HapticCueSettings(intensity: .nan, pulses: 1), HapticCueSettings(intensity: 1, pulses: 11), HapticCueSettings(intensity: 1, pulses: 0), HapticCueSettings(intensity: 1, pulses: 1, spacing: 0.01)] {
            settings.cues[.restEnded] = cue
            XCTAssertFalse(settings.isValid)
            XCTAssertTrue(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).isEmpty)
        }
    }
    func testStrongDefaultsUseSustainedFullIntensityBurstsWithNonOverlappingGaps() {
        let settings = FitHapticSettings()
        let pulses = HapticPatternPolicy.pulses(for: .restEnded, settings: settings)
        XCTAssertEqual(settings.strength, 1)
        XCTAssertEqual(pulses.count, 5)
        XCTAssertTrue(pulses.allSatisfy { $0.duration == 0.45 && $0.intensity == 1 })
        XCTAssertEqual(pulses.last!.endTime, 3.25, accuracy: 0.0001)
        for index in 1..<pulses.count {
            XCTAssertEqual(pulses[index].time - pulses[index - 1].endTime, 0.25, accuracy: 0.0001)
        }
        XCTAssertEqual(HapticPatternPolicy.pulses(for: .selection, settings: settings).first?.duration, 0)
    }
    func testLongPatternBoundsAndPresetKeepMasterOffAndUnrelatedCustomizations() {
        var settings = FitHapticSettings()
        settings.cues[.restEnded] = HapticCueSettings(intensity: 1, pulses: 10, spacing: 1, duration: 0.8)
        XCTAssertTrue(settings.isValid)
        XCTAssertEqual(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).last!.endTime, 17, accuracy: 0.0001)
        for duration in [-0.1, 0.81, .infinity, .nan] {
            settings.cues[.restEnded]?.duration = duration
            XCTAssertFalse(settings.isValid)
            XCTAssertTrue(HapticPatternPolicy.pulses(for: .restEnded, settings: settings).isEmpty)
        }
        settings.enabled = false; settings.strength = 0.2
        let selection = HapticCueSettings(enabled: false, intensity: 0.1, pulses: 1)
        settings.cues[.selection] = selection
        settings.useStrongWorkoutCues()
        XCTAssertEqual(settings.strength, 1)
        XCTAssertEqual(settings.cue(.restEnded), FitHapticEvent.restEnded.defaults)
        XCTAssertEqual(settings.cue(.selection), selection)
        XCTAssertFalse(settings.enabled)
    }
    func testLegacySettingsDecodeWithoutLosingCustomStrengthOrNotificationOptIn() throws {
        var original = FitHapticSettings(); original.strength = 0.35; original.backgroundRestAlerts = true
        original.cues[.restEnded] = HapticCueSettings(intensity: 0.6, pulses: 4, spacing: 0.3, feel: .soft)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["version"] = 1; json.removeValue(forKey: "restAlertMode")
        let restored = try JSONDecoder().decode(FitHapticSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(restored.isValid); XCTAssertEqual(restored.version, 2)
        XCTAssertEqual(restored.strength, 0.35); XCTAssertEqual(restored.restAlertMode, .notification)
        XCTAssertTrue(restored.backgroundRestAlerts)
        XCTAssertEqual(restored.cue(.restEnded), original.cue(.restEnded))
        XCTAssertEqual(HapticPatternPolicy.pulses(for: .restEnded, settings: restored)[3].time, 0.9, accuracy: 0.0001)
        XCTAssertEqual(HapticPatternPolicy.pulses(for: .restEnded, settings: restored)[0].duration, 0)
        XCTAssertEqual(try JSONDecoder().decode(FitHapticSettings.self, from: JSONEncoder().encode(restored)), restored)
    }
    @MainActor func testLongFinalPulseRemainsProtectedFromLowerPriorityFeedback() {
        let defaults = UserDefaults(suiteName: "haptics-tail-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let output = HapticOutputStub(), service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: output)
        var settings = service.settings
        settings.cues[.restEnded] = HapticCueSettings(intensity: 1, pulses: 1, duration: 0.8)
        XCTAssertTrue(service.update(settings)); service.sceneChanged(active: true)
        service.play(.restEnded, now: time)
        service.play(.selection, now: time.addingTimeInterval(0.7))
        service.play(.coachReply, now: time.addingTimeInterval(0.7))
        XCTAssertEqual(output.patterns.count, 1)
        service.play(.selection, now: time.addingTimeInterval(0.9))
        XCTAssertEqual(output.patterns.count, 2)
    }
    @MainActor func testSettingsRelaunchKeepsAllCuesAndHonorsTheExistingMasterPreference() throws {
        let defaults = UserDefaults(suiteName: "haptics-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let repo = HapticPreferencesStub(); repo.preferences.appearance = .light; repo.preferences.hapticsEnabled = false
        let service = HapticService(defaults: defaults, repository: repo, output: HapticOutputStub())
        XCTAssertFalse(service.settings.enabled)
        var next = service.settings; next.enabled = true; next.strength = 0.4
        next.cues[.restEnded] = HapticCueSettings(intensity: 0.5, pulses: 4, spacing: 0.4, feel: .crisp, duration: 0.45)
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
        service.play(.selection, now: time.addingTimeInterval(4))
        XCTAssertEqual(output.patterns.count, 3)
        service.sceneChanged(active: false)
        service.play(.restEnded, now: time.addingTimeInterval(5))
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
        XCTAssertEqual(output.patterns.last?.count, FitHapticEvent.restEnded.defaults.pulses)
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
    @MainActor func testNativeAlarmIsBackgroundOnlyAndRefreshesOrCancelsAcrossWorkoutActions() async throws {
        let defaults = UserDefaults(suiteName: "haptics-alarm-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let output = HapticOutputStub(), service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: output)
        let alerts = RestAlertStub(); alerts.supportsAlarm = true
        let coordinator = WorkoutHapticCoordinator(store: store, haptics: service, alerts: alerts)
        service.onSettingsChange = { [weak coordinator] in coordinator?.settingsChanged() }
        store.onMutation = { [weak coordinator] before, after, date in coordinator?.saved(before: before, after: after, at: date) }
        coordinator.sceneChanged(active: true)
        await coordinator.setAlertMode(.alarm)
        XCTAssertEqual(alerts.requests, 0)
        await coordinator.setBackgroundAlerts(true)
        XCTAssertEqual(alerts.requestedModes, [.alarm])
        let draft = QuickWorkoutDraft(entries: [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(restSeconds: 90), WorkoutSet()])])
        XCTAssertTrue(store.startQuickWorkout(draft, unit: .kg))
        let id = try XCTUnwrap(store.active?.id)
        XCTAssertTrue(store.performFocused(.completeSet, sessionID: id)); await coordinator.flushAlerts()
        XCTAssertNil(alerts.current)
        coordinator.sceneChanged(active: false); await coordinator.flushAlerts()
        let first = try XCTUnwrap(alerts.current)
        XCTAssertEqual(first.mode, .alarm)
        XCTAssertEqual(first.deadline, store.active?.restUntil)
        XCTAssertTrue(store.performFocused(.extendRest, sessionID: id)); await coordinator.flushAlerts()
        XCTAssertEqual(alerts.current?.deadline, first.deadline.addingTimeInterval(15))
        store.pause(); await coordinator.flushAlerts(); XCTAssertNil(alerts.current)
        store.resume(); await coordinator.flushAlerts(); XCTAssertNotNil(alerts.current)
        coordinator.sceneChanged(active: true); await coordinator.flushAlerts(); XCTAssertNil(alerts.current)
        coordinator.sceneChanged(active: false); await coordinator.flushAlerts(); XCTAssertNotNil(alerts.current)
        XCTAssertTrue(store.performFocused(.skipRest, sessionID: id)); await coordinator.flushAlerts(); XCTAssertNil(alerts.current)
        XCTAssertEqual(alerts.requests, 1)
    }
    @MainActor func testAlarmPermissionDenialRetainsPreviousModeAndUnsupportedOSUsesNotifications() async throws {
        let defaults = UserDefaults(suiteName: "haptics-mode-" + UUID().uuidString)!
        defer { defaults.removeObject(forKey: HapticService.storageKey) }
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        let service = HapticService(defaults: defaults, repository: HapticPreferencesStub(), output: HapticOutputStub())
        let alerts = RestAlertStub(), coordinator = WorkoutHapticCoordinator(store: store, haptics: service, alerts: alerts)
        XCTAssertEqual(coordinator.alertMode, .notification)
        await coordinator.setBackgroundAlerts(true)
        XCTAssertEqual(alerts.requestedModes, [.notification])
        XCTAssertEqual(service.settings.restAlertMode, .notification)
        alerts.supportsAlarm = true
        await coordinator.setAlertMode(.notification)
        let before = service.settings
        alerts.authorized = false
        await coordinator.setAlertMode(.alarm)
        XCTAssertEqual(service.settings, before)
        XCTAssertNotNil(coordinator.error)
        XCTAssertEqual(alerts.requestedModes.last, .alarm)
        alerts.authorized = true
        await coordinator.setAlertMode(.alarm)
        XCTAssertEqual(service.settings.restAlertMode, .alarm)
        XCTAssertTrue(service.settings.backgroundRestAlerts)
        XCTAssertTrue(coordinator.alertsAuthorized)
        service.setEnabled(false); coordinator.settingsChanged(); await coordinator.flushAlerts()
        XCTAssertNil(alerts.current)
    }
    @MainActor func testRestAlertDispatcherUsesExactlyOneChannelAndClearsBothOnCancellation() async throws {
        let notifications = RestChannelStub(), alarms = RestChannelStub()
        let dispatcher = SystemWorkoutRestAlerts(notifications: notifications, alarms: alarms)
        XCTAssertTrue(dispatcher.supportsAlarm)
        var alert = WorkoutRestAlert(sessionID: UUID(), deadline: time.addingTimeInterval(30), mode: .alarm)
        let granted = try await dispatcher.requestAccess(for: .alarm)
        XCTAssertTrue(granted)
        XCTAssertEqual(alarms.requests, 1); XCTAssertEqual(notifications.requests, 0)
        try await dispatcher.replace(alert)
        XCTAssertNil(notifications.current); XCTAssertEqual(alarms.current, alert)
        alert.mode = .notification
        try await dispatcher.replace(alert)
        XCTAssertNil(alarms.current); XCTAssertEqual(notifications.current, alert)
        try await dispatcher.replace(nil)
        XCTAssertNil(alarms.current); XCTAssertNil(notifications.current)
        let unsupported = SystemWorkoutRestAlerts(notifications: notifications, alarms: nil)
        alert.mode = .alarm
        try await unsupported.replace(alert)
        XCTAssertEqual(notifications.current, alert)
    }
    @MainActor func testRestAlertCancellationAttemptsBothChannelsEvenIfOneFails() async throws {
        let notifications = RestChannelStub(), alarms = RestChannelStub()
        let dispatcher = SystemWorkoutRestAlerts(notifications: notifications, alarms: alarms)
        let alert = WorkoutRestAlert(sessionID: UUID(), deadline: time.addingTimeInterval(30), mode: .alarm)
        try await dispatcher.replace(alert)
        notifications.fail = true
        do { try await dispatcher.replace(nil); XCTFail("Expected the cancellation error") } catch { }
        XCTAssertNil(alarms.current)
        XCTAssertEqual(alarms.replacements, 2)
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
    var supportsAlarm = false
    var current: WorkoutRestAlert?
    var requests = 0
    var requestedModes: [WorkoutRestAlertMode] = []
    var authorized = true
    func replace(_ alert: WorkoutRestAlert?) async throws { current = alert }
    func requestAccess(for mode: WorkoutRestAlertMode) async throws -> Bool { requests += 1; requestedModes.append(mode); return authorized }
    func isAuthorized(for mode: WorkoutRestAlertMode) async -> Bool { authorized }
}
@MainActor private final class RestChannelStub: WorkoutRestAlertChannel {
    var current: WorkoutRestAlert?
    var requests = 0
    var replacements = 0
    var fail = false
    func replace(_ alert: WorkoutRestAlert?) async throws {
        replacements += 1
        if fail { throw CocoaError(.fileWriteUnknown) }
        current = alert
    }
    func requestAccess() async throws -> Bool { requests += 1; return true }
    func isAuthorized() async -> Bool { true }
}

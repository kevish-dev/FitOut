import Foundation
import UserNotifications
import UIKit
import Observation

enum WorkoutHapticPolicy {
    static func event(before: WorkoutSession?, after: WorkoutSession?, now: Date) -> FitHapticEvent? {
        guard let after else { return nil }
        guard let before, before.id == after.id else { return after.isActive ? .workoutStarted : nil }
        if after.status == .completed && before.status != .completed { return .workoutCompleted }
        if after.status != before.status {
            if after.status == .paused || before.status == .paused && after.isActive { return .pauseResume }
            if after.status == .abandoned || after.status == .skipped { return .warning }
        }
        if after.completedSets.count > before.completedSets.count { return .setCompleted }
        if after.skippedSets.count > before.skippedSets.count { return .setSkipped }
        if let deadline = before.restUntil, after.restUntil == nil, after.status == .inProgress,
           after.execution?.phase != .resting {
            return deadline <= now ? .restEnded : .selection
        }
        if after.execution?.phase == .activeSet, before.execution?.phase != .activeSet {
            return before.execution?.phase == .exerciseTransition ? .nextExercise : .nextSet
        }
        if before.restUntil != after.restUntil { return .selection }
        if after.completedSets.count < before.completedSets.count || after.skippedSets.count < before.skippedSets.count { return .selection }
        return nil
    }
}

struct WorkoutRestAlert: Equatable, Sendable {
    let sessionID: UUID
    let deadline: Date
    static func make(session: WorkoutSession?, settings: FitHapticSettings, now: Date) -> Self? {
        guard settings.shouldAlertForRest, let session, session.status == .inProgress,
              session.execution?.phase == .resting, let deadline = session.restUntil,
              deadline > now, !session.pendingWork.isEmpty else { return nil }
        return Self(sessionID: session.id, deadline: deadline)
    }
}

@MainActor protocol WorkoutRestAlertScheduling {
    func replace(_ alert: WorkoutRestAlert?) async throws
    func requestAccess() async throws -> Bool
    func isAuthorized() async -> Bool
}

@MainActor final class SystemWorkoutRestAlerts: WorkoutRestAlertScheduling {
    private let center = UNUserNotificationCenter.current()
    func requestAccess() async throws -> Bool {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined { return try await center.requestAuthorization(options: [.alert, .sound]) }
        return await isAuthorized()
    }
    func isAuthorized() async -> Bool {
        let value = await center.notificationSettings().authorizationStatus
        return value == .authorized || value == .provisional || value == .ephemeral
    }
    func replace(_ alert: WorkoutRestAlert?) async throws {
        let id = WorkoutNotificationRouter.restIdentifier
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        guard let alert, await isAuthorized(), alert.deadline > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest finished"
        content.body = "Your next set or exercise is ready. Open FitOut to continue."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, alert.deadline.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// Installed at app startup, before a cold-launch notification tap can arrive.
@MainActor @Observable final class WorkoutNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WorkoutNotificationRouter()
    nonisolated static let restIdentifier = "fitout.workout.rest.finished"
    var openWorkout = false
    func install() { UNUserNotificationCenter.current().delegate = self }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.restIdentifier else { return }
        await MainActor.run { self.openWorkout = true }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Foreground rest completion has exactly one custom cue. Existing reminder
        // behavior also stays quiet while the app is in front.
        []
    }
}

/// Owns the rest deadline independently of the workout editor's visibility.
@MainActor @Observable final class WorkoutHapticCoordinator {
    private let store: WorkoutStore
    private let haptics: HapticService
    private let alerts: any WorkoutRestAlertScheduling
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var active = false
    @ObservationIgnored private var recovering = false
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var scheduled: WorkoutRestAlert?
    @ObservationIgnored private var desiredAlert: WorkoutRestAlert?
    @ObservationIgnored private var hasPendingAlert = false
    @ObservationIgnored private var hasSynchronizedAlert = false
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    private(set) var alertsAuthorized = false
    private(set) var isRequesting = false
    private(set) var error: String?

    init(store: WorkoutStore, haptics: HapticService, alerts: (any WorkoutRestAlertScheduling)? = nil,
         enabled: Bool = true, clock: @escaping () -> Date = { .now }) {
        self.store = store; self.haptics = haptics; self.alerts = alerts ?? SystemWorkoutRestAlerts()
        self.enabled = enabled; self.clock = clock
    }
    func saved(before: WorkoutSession?, after: WorkoutSession?, at now: Date) {
        if let event = WorkoutHapticPolicy.event(before: before, after: after, now: now), !(recovering && event == .restEnded) { haptics.play(event, now: now) }
        synchronize()
    }
    func sceneChanged(active: Bool) {
        self.active = active
        hasSynchronizedAlert = false
        haptics.sceneChanged(active: active)
        if active, let session = store.active, session.status == .inProgress,
           session.restUntil.map({ $0 <= clock() }) == true {
            // Background delivery is controlled by iOS; never replay an old cue.
            recovering = true; _ = store.prepareFocusedSession(session.id, now: clock()); recovering = false
        }
        synchronize()
    }
    func settingsChanged() { synchronize() }
    func refreshAuthorization() async { alertsAuthorized = await alerts.isAuthorized() }
    func setBackgroundAlerts(_ value: Bool) async {
        guard !isRequesting else { return }
        isRequesting = true; error = nil
        defer { isRequesting = false }
        do {
            if value {
                alertsAuthorized = try await alerts.requestAccess()
                guard alertsAuthorized else { error = "Notifications are disabled for FitOut. Enable them in iPhone Settings for background rest alerts."; return }
            }
            var next = haptics.settings; next.backgroundRestAlerts = value
            _ = haptics.update(next)
        } catch { self.error = "The rest alert preference could not be enabled. Try again." }
    }
    func flushAlerts() async { await alertTask?.value }
    private func synchronize() {
        guard enabled else { return }
        let now = clock()
        let requested = WorkoutRestAlert.make(session: store.active, settings: haptics.settings, now: now)
        if !hasSynchronizedAlert || requested != desiredAlert {
            desiredAlert = requested; hasPendingAlert = true; hasSynchronizedAlert = true
        }
        if alertTask == nil {
            // Serialize replacements: an old async add cannot win over pause/off.
            alertTask = Task { [weak self] in
                guard let self else { return }
                while self.hasPendingAlert {
                    self.hasPendingAlert = false
                    do { try await self.alerts.replace(self.desiredAlert) }
                    catch { self.error = "The background rest alert could not be scheduled. Foreground haptics still work." }
                }
                self.alertTask = nil
            }
        }
        let next: WorkoutRestAlert?
        if active, let session = store.active, session.status == .inProgress,
           session.execution?.phase == .resting, let deadline = session.restUntil {
            next = WorkoutRestAlert(sessionID: session.id, deadline: deadline)
        } else { next = nil }
        guard next != scheduled else { return }
        restTask?.cancel(); restTask = nil; scheduled = next
        guard let next else { return }
        restTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, next.deadline.timeIntervalSince(now)))) } catch { return }
            guard let self, !Task.isCancelled, self.active, self.store.active?.id == next.sessionID,
                  self.store.active?.status == .inProgress, self.store.active?.restUntil == next.deadline else { return }
            self.scheduled = nil; self.restTask = nil
            _ = self.store.prepareFocusedSession(next.sessionID, now: self.clock())
        }
    }
}

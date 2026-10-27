// AlarmManager's SDK interface predates complete Swift concurrency annotations.
@preconcurrency import AlarmKit
import AppIntents
import Foundation
import SwiftUI

@available(iOS 26.0, *)
private struct WorkoutRestAlarmMetadata: AlarmMetadata {}

/// A fixed-date alert reuses the workout's existing Live Activity countdown.
/// AlarmKit owns ringing, vibration, Lock Screen presentation and dismissal.
@available(iOS 26.0, *)
@MainActor final class AlarmKitWorkoutRestAlerts: WorkoutRestAlertChannel {
    private static let identifier = UUID(uuidString: "F1700000-0000-4000-8000-000000000001")!
    private let manager = AlarmManager.shared

    func requestAccess() async throws -> Bool {
        if manager.authorizationState == .notDetermined { return try await manager.requestAuthorization() == .authorized }
        return manager.authorizationState == .authorized
    }
    func isAuthorized() async -> Bool { manager.authorizationState == .authorized }
    func replace(_ alert: WorkoutRestAlert?) async throws {
        // Never implicitly request permission from a save/background transition.
        guard manager.authorizationState == .authorized else { return }
        if try manager.alarms.contains(where: { $0.id == Self.identifier }) { try manager.cancel(id: Self.identifier) }
        guard let alert, alert.deadline > .now else { return }
        let open = AlarmButton(text: "Open workout", textColor: .white, systemImageName: "figure.strengthtraining.traditional")
        let presentation: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            presentation = AlarmPresentation.Alert(title: "Rest finished — next set ready", secondaryButton: open, secondaryButtonBehavior: .custom)
        } else {
            presentation = AlarmPresentation.Alert(title: "Rest finished — next set ready",
                stopButton: AlarmButton(text: "Dismiss", textColor: .white, systemImageName: "xmark"),
                secondaryButton: open, secondaryButtonBehavior: .custom)
        }
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: presentation), metadata: WorkoutRestAlarmMetadata(), tintColor: Color(red: 1, green: 0.302, blue: 0))
        let configuration = AlarmManager.AlarmConfiguration(schedule: .fixed(alert.deadline), attributes: attributes,
            secondaryIntent: OpenWorkoutFromRestAlarm(), sound: .default)
        _ = try await manager.schedule(id: Self.identifier, configuration: configuration)
    }
}

@available(iOS 26.0, *)
struct OpenWorkoutFromRestAlarm: LiveActivityIntent {
    static let title: LocalizedStringResource = "Open workout after rest"
    static let openAppWhenRun = true
    static let isDiscoverable = false
    func perform() async throws -> some IntentResult {
        await MainActor.run { WorkoutNotificationRouter.shared.openWorkout = true }
        return .result()
    }
}

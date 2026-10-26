import SwiftUI
import UIKit

@main
struct FitOutApp: App {
    init() {
        WorkoutNotificationRouter.shared.install()
        let navigationBar = UINavigationBar.appearance()
        navigationBar.titleTextAttributes = [.font: UIFont(name: "Orbitron-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)]
        navigationBar.largeTitleTextAttributes = [.font: UIFont(name: "Orbitron-Bold", size: 28) ?? UIFont.boldSystemFont(ofSize: 28)]
    }

    var body: some Scene {
        WindowGroup { AppRoot().font(FitTheme.body()).tint(FitTheme.orange) }
    }
}

struct AppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var container: AppContainer?
    @State private var failure: String?
    @State private var hasFinishedOpening = false
    @State private var widgetDestination: WidgetDestination?
    @State private var widgetRouteID = UUID()
    @State private var restNotification = WorkoutNotificationRouter.shared
    var body: some View {
        Group {
            if let container, hasFinishedOpening {
                if container.profile.draft.completedAt != nil {
                    AppShell(container: container, widgetDestination: $widgetDestination)
                        .id(widgetRouteID)
                } else { ProfileFlow(store: container.profile) }
            } else if let failure {
                ContentUnavailableView {
                    Label("Your data could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved files are preserved. \(failure)")
                } actions: { Button("Retry", action: open).buttonStyle(.borderedProminent) }
            } else if hasFinishedOpening {
                ProgressView("Opening FitOut…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear.ignoresSafeArea()
            }
        }.preferredColorScheme(container?.presentation.appearance.colorScheme)
        .environment(\.appNavigationStyle, container?.presentation.navigationStyle ?? .topRight)
        .environment(\.fitHaptics, container?.haptics)
        .overlay {
            if !hasFinishedOpening {
                AppOpeningView { finishOpening() }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .statusBarHidden(!hasFinishedOpening)
        .task { open(); openRestNotification() }
        .onChange(of: scenePhase) { _, phase in
            container?.workoutHaptics.sceneChanged(active: phase == .active)
            // Returning from another app must never replay an unfinished intro.
            if phase == .background { finishOpening(animated: false) }
        }
        .onChange(of: restNotification.openWorkout) { _, _ in openRestNotification() }
        .onOpenURL { url in
            if let destination = WidgetDestination(url: url) {
                widgetDestination = destination
                widgetRouteID = UUID()
                finishOpening(animated: false)
            }
        }
    }
    private func finishOpening(animated: Bool = true) {
        guard !hasFinishedOpening else { return }
        withAnimation(animated ? .easeOut(duration: reduceMotion ? 0.12 : 0.18) : nil) {
            hasFinishedOpening = true
        }
    }
    private func open() {
        do {
            container = try WorkoutRuntime.shared(); failure = nil
            container?.workoutHaptics.sceneChanged(active: scenePhase == .active)
        }
        catch {
            failure = error.localizedDescription
            finishOpening(animated: false)
        }
    }
    private func openRestNotification() {
        guard restNotification.openWorkout, container != nil else { return }
        restNotification.openWorkout = false
        widgetDestination = .workout; widgetRouteID = UUID(); finishOpening(animated: false)
    }
}

import SwiftUI
import UIKit

@main
struct FitOutApp: App {
    init() {
        let navigationBar = UINavigationBar.appearance()
        navigationBar.titleTextAttributes = [.font: UIFont(name: "Orbitron-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)]
        navigationBar.largeTitleTextAttributes = [.font: UIFont(name: "Orbitron-Bold", size: 28) ?? UIFont.boldSystemFont(ofSize: 28)]
    }

    var body: some Scene {
        WindowGroup { AppRoot().font(FitTheme.body()).tint(FitTheme.orange).preferredColorScheme(.dark) }
    }
}

struct AppRoot: View {
    @State private var container: AppContainer?
    @State private var failure: String?
    @State private var widgetDestination: WidgetDestination?
    @State private var widgetRouteID = UUID()
    var body: some View {
        Group {
            if let container {
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
            } else { ProgressView("Opening FitOut…").task { open() } }
        }.onOpenURL { url in
            if let destination = WidgetDestination(url: url) { widgetDestination = destination; widgetRouteID = UUID() }
        }
    }
    private func open() {
        do { container = try WorkoutRuntime.shared(); failure = nil }
        catch { failure = error.localizedDescription }
    }
}

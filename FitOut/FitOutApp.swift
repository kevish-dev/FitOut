import SwiftUI

@main
struct FitOutApp: App {
    var body: some Scene {
        WindowGroup { AppRoot().tint(FitTheme.orange).preferredColorScheme(.dark) }
    }
}

struct AppRoot: View {
    @State private var container: AppContainer?
    @State private var failure: String?
    var body: some View {
        Group {
            if let container {
                if container.profile.draft.completedAt != nil {
                    AppShell(container: container)
                } else { ProfileFlow(store: container.profile) }
            } else if let failure {
                ContentUnavailableView {
                    Label("Your data could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("Your saved files are preserved. \(failure)")
                } actions: { Button("Retry", action: open).buttonStyle(.borderedProminent) }
            } else { ProgressView("Opening FitOut…").task { open() } }
        }
    }
    private func open() {
        do { container = try AppContainer.live(); failure = nil }
        catch { failure = error.localizedDescription }
    }
}

import SwiftUI

@main
struct FitOutApp: App {
    @State private var store = OnboardingStore()
    var body: some Scene {
        WindowGroup {
            OnboardingView(store: store)
                .preferredColorScheme(.dark)
                .tint(FitTheme.orange)
        }
    }
}

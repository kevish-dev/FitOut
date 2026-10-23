import SwiftUI

struct AppShell: View {
    let container: AppContainer
    @State private var tab = 0
    @State private var menuOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case 1: GymView(store: container.gym, workouts: container.workouts, unit: container.profile.draft.weightUnit, defaults: container.defaults)
                case 2: ModuleEmpty(title: "Nutrition", symbol: "fork.knife", detail: "No meals or water have been logged.")
                case 3: HealthConnectionView(service: container.health)
                case 4: ModuleEmpty(title: "AI Coach", symbol: "sparkles", detail: container.capabilities.currentCapabilities().foundationModels.explanation)
                case 5: FoundationSettings(container: container)
                default: HomeView(container: container, tab: $tab)
                }
            }
        }
        .id(tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(FitTheme.dashboardBackground.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { menuOpen.toggle() }
                } label: {
                    Image(systemName: "house")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 52, height: 52)
                        .foregroundStyle(FitTheme.dashboardAccent)
                        .dashboardGlass(in: Circle(), highlighted: true, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Navigation menu")
                .accessibilityValue(menuOpen ? "Expanded" : "Collapsed")
                .accessibilityHint("Shows Home, Gym, Nutrition, Health and AI Coach. Tap again to close.")
                .accessibilityIdentifier("navigationMenuButton")

                if menuOpen {
                    VStack(spacing: 10) {
                        navigationButton("Home", symbol: "house", destination: 0)
                        navigationButton("Gym", symbol: "dumbbell", destination: 1)
                        navigationButton("Nutrition", symbol: "fork.knife", destination: 2)
                        navigationButton("Health", symbol: "heart", destination: 3)
                        navigationButton("AI Coach", symbol: "sparkles", destination: 4)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
        .accessibilityAction(.escape) { menuOpen = false }
        .onChange(of: tab) { _, _ in menuOpen = false }
    }

    private func select(_ destination: Int) {
        menuOpen = false
        tab = destination
    }

    private func navigationButton(_ title: String, symbol: String, destination: Int) -> some View {
        Button { select(destination) } label: {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular))
            .foregroundStyle(tab == destination ? FitTheme.dashboardAccent : .white)
            .frame(width: 52, height: 52)
            .dashboardGlass(in: Circle(), highlighted: tab == destination, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(tab == destination ? .isSelected : [])
        .accessibilityIdentifier("navigate-\(destination)")
    }
}

struct ModuleEmpty: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(detail)).navigationTitle(title) }
}

struct FoundationSettings: View {
    let container: AppContainer
    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: container.profile.draft.trimmedName)
                NavigationLink("Edit profile") { ProfileEditor(store: container.profile) }
            }
            NavigationLink("Apple Health") { HealthConnectionView(service: container.health) }
            Section("Privacy") { Text("FitOut stores your data on this iPhone. No account, analytics, or external AI service is used.") }
            Section("Device capabilities") {
                LabeledContent("Apple Health", value: container.capabilities.currentCapabilities().healthKit.explanation)
                LabeledContent("Apple Intelligence", value: container.capabilities.currentCapabilities().foundationModels.explanation)
            }
        }.navigationTitle("Settings")
    }
}

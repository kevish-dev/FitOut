import SwiftUI

struct AppShell: View {
    let container: AppContainer
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(container: container, tab: $tab) }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { GymView(store: container.gym) }
                .tabItem { Label("Gym", systemImage: "dumbbell") }.tag(1)
            NavigationStack { ModuleEmpty(title: "Nutrition", symbol: "fork.knife", detail: "No meals or water have been logged.") }
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }.tag(2)
            NavigationStack { HealthConnectionView(service: container.health) }
                .tabItem { Label("Health", systemImage: "heart") }.tag(3)
            NavigationStack { ModuleEmpty(title: "AI Coach", symbol: "sparkles", detail: container.capabilities.currentCapabilities().foundationModels.explanation) }
                .tabItem { Label("AI Coach", systemImage: "sparkles") }.tag(4)
        }
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

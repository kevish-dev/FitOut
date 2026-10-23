import SwiftUI

struct AppShell: View {
    let container: AppContainer
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                List {
                    Section { Text("Welcome, \(container.profile.draft.trimmedName)").font(.title2.bold()) }
                    Section("Get started") {
                        Button("Gym routines") { tab = 1 }
                        Button("Nutrition and hydration") { tab = 2 }
                        Button("Apple Health") { tab = 3 }
                    }
                    NavigationLink("Settings") { FoundationSettings(container: container) }
                }.navigationTitle("Home")
            }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack { ModuleEmpty(title: "Gym", symbol: "dumbbell", detail: "Your routines and workout history will appear here.") }
                .tabItem { Label("Gym", systemImage: "dumbbell") }.tag(1)
            NavigationStack { ModuleEmpty(title: "Nutrition", symbol: "fork.knife", detail: "No meals or water have been logged.") }
                .tabItem { Label("Nutrition", systemImage: "fork.knife") }.tag(2)
            NavigationStack { ModuleEmpty(title: "Health", symbol: "heart", detail: container.capabilities.currentCapabilities().healthKit.isAvailable ? "Apple Health is optional. No health data has been requested." : container.capabilities.currentCapabilities().healthKit.explanation) }
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
            Section("Privacy") { Text("FitOut stores your data on this iPhone. No account, analytics, or external AI service is used.") }
            Section("Device capabilities") {
                LabeledContent("Apple Health", value: container.capabilities.currentCapabilities().healthKit.explanation)
                LabeledContent("Apple Intelligence", value: container.capabilities.currentCapabilities().foundationModels.explanation)
            }
        }.navigationTitle("Settings")
    }
}

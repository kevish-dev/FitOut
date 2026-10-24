import SwiftUI
import Combine

struct AppShell: View {
    let container: AppContainer
    @Binding var widgetDestination: WidgetDestination?
    @State private var tab = 0
    @State private var menuOpen = false
    @State private var widgetSheet: WidgetDestination?
    @State private var widgetError: String?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            Group {
                switch tab {
                case 1: GymView(store: container.gym, workouts: container.workouts, unit: container.profile.draft.weightUnit, defaults: container.defaults)
                case 2: NutritionView(container: container)
                case 3: HealthConnectionView(service: container.health)
                case 4: CoachView(store: container.coach, profile: container.profile.draft)
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
                    Image(systemName: menuOpen ? "xmark" : "line.3.horizontal")
                        .font(.system(size: 22, weight: .regular))
                        .frame(width: 52, height: 52)
                        .foregroundStyle(FitTheme.dashboardAccent)
                        .dashboardGlass(in: Circle(), highlighted: true, interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(menuOpen ? "Close navigation menu" : "Open navigation menu")
                .accessibilityValue(menuOpen ? "Expanded" : "Collapsed")
                .accessibilityHint(menuOpen ? "Hides the navigation destinations." : "Shows Home, Gym, Nutrition, Health and AI Coach.")
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
            // Center the 52 pt menu control on the native 44 pt navigation row.
            .padding(.top, -4)
            .padding(.trailing, FitTheme.pageInset)
        }
        .accessibilityAction(.escape) { menuOpen = false }
        .onChange(of: tab) { _, _ in menuOpen = false }
        .task { openPendingWidget() }
        .onChange(of: widgetDestination) { _, _ in openPendingWidget() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            container.widgets.publish()
            if phase == .active { Task { await container.health.refreshOverview() } }
        }
        .task(id: phase) {
            container.workoutPresentation.sceneChanged(active: phase == .active)
            guard phase == .active else { return }
            container.hydration.refresh()
            container.widgets.publish()
            if container.health.lastRefreshedAt.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                await container.health.refreshOverview()
            }
        }
        .sheet(item: $widgetSheet) { destination in
            if destination == .routine {
                RoutineEditor(store: container.gym, routine: container.gym.resumableDraft?.routine ?? container.gym.activeRoutine ?? RoutineTemplate.custom.make(), unit: container.profile.draft.weightUnit)
            } else {
                NavigationStack {
                    Group {
                        switch destination {
                        case .water: HydrationView(store: container.hydration, health: container.health, reminders: container.hydrationReminders)
                        case .workout: ActiveWorkoutView(store: container.workouts, gym: container.gym, unit: container.profile.draft.weightUnit, defaults: container.defaults)
                        case .analytics: AnalyticsView(store: container.workouts, gym: container.gym, unit: container.profile.draft.weightUnit)
                        case .history: WorkoutHistory(store: container.workouts, unit: container.profile.draft.weightUnit)
                        default: EmptyView()
                        }
                    }.toolbar { if destination != .workout { Button("Close") { widgetSheet = nil } } }
                }
            }
        }
        .alert("Workout could not open", isPresented: Binding(get: { widgetError != nil }, set: { if !$0 { widgetError = nil } })) {
            Button("OK", role: .cancel) { widgetError = nil }
        } message: { Text(widgetError ?? "") }
    }

    private func openPendingWidget() {
        guard let destination = widgetDestination else { return }
        widgetDestination = nil
        menuOpen = false
        switch destination {
        case .home: tab = 0
        case .health: tab = 3
        case .nutrition: tab = 2
        case .startWorkout:
            tab = 1
            if container.workouts.active != nil {
                container.workouts.resume()
                openWorkout()
            } else if let routine = container.gym.activeRoutine,
                      routine.hasStarted(at: .now), let day = RoutineSchedule.day(in: routine, at: .now),
                      day.kind == .workout, !day.exercises.isEmpty {
                if container.workouts.history.contains(where: { $0.status == .completed && $0.routineID == routine.id && Calendar.current.isDateInToday($0.startedAt) }) { widgetSheet = .history }
                else if container.workouts.start(day: day, routineID: routine.id, catalogue: container.gym.exercises) { openWorkout() }
                else { widgetError = container.workouts.error }
            } else { widgetSheet = .routine }
        case .workout:
            tab = 1
            if container.workouts.active != nil { openWorkout() }
        default: widgetSheet = destination
        }
    }

    private func openWorkout() {
        if !container.workoutPresentation.openCurrentWorkout() { widgetSheet = .workout }
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
            NavigationLink("Water intake") { HydrationView(store: container.hydration, health: container.health, reminders: container.hydrationReminders) }
            NavigationLink("Widgets & goals") { WidgetGoalsView(store: container.hydration) }
            Section("Privacy") { Text("FitOut stores your data on this iPhone. No account, analytics, or external AI service is used.") }
            Section("Device capabilities") {
                LabeledContent("Apple Health", value: container.capabilities.currentCapabilities().healthKit.explanation)
                LabeledContent("Apple Intelligence", value: container.capabilities.currentCapabilities().foundationModels.explanation)
            }
        }.navigationTitle("Settings")
    }
}

import SwiftUI
import Combine

struct AppShell: View {
    let container: AppContainer
    @Binding var widgetDestination: WidgetDestination?
    @State private var tab = 0
    @State private var navigationRevisions: [Int: UUID] = [:]
    @State private var menuOpen = false
    @State private var widgetSheet: WidgetDestination?
    @State private var widgetError: String?
    @State private var keyboardVisible = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        nativeTabs
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(FitTheme.textPrimary)
        .background(FitTheme.dashboardBackground.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if container.presentation.navigationStyle == .topRight {
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
                            ForEach(AppSection.allCases) { destination in
                                navigationButton(destination.title, symbol: destination.symbol, destination: destination.rawValue)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .modifier(NavigationGlassGroup())
                // Center the 52 pt menu control on the native 44 pt navigation row.
                .padding(.top, -4)
                .padding(.trailing, FitTheme.pageInset)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onChange(of: container.presentation.navigationStyle) { _, _ in menuOpen = false }
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

    @ViewBuilder private var nativeTabs: some View {
        if #available(iOS 26.0, *) {
            tabContent.tabBarMinimizeBehavior(.never)
        } else { tabContent }
    }
    private var tabContent: some View {
        TabView(selection: Binding(get: { tab }, set: select)) {
            ForEach(AppSection.allCases) { section in
                NavigationStack { sectionContent(section) }
                    .id("\(section.rawValue)-\(navigationRevisions[section.rawValue]?.uuidString ?? "root")")
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .tag(section.rawValue)
                    .toolbar(container.presentation.navigationStyle == .bottomBar && !keyboardVisible ? .visible : .hidden, for: .tabBar)
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(FitTheme.dashboardAccent)
        .background(WorkoutControlLayoutReader())
    }
    @ViewBuilder private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView(container: container, tab: $tab)
        case .gym: GymView(store: container.gym, workouts: container.workouts, unit: container.profile.draft.weightUnit, defaults: container.defaults)
        case .nutrition: NutritionView(container: container)
        case .health: HealthConnectionView(service: container.health)
        case .coach: CoachView(store: container.coach, profile: container.profile.draft)
        }
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
        if tab == destination { navigationRevisions[destination] = UUID() }
        else { tab = destination }
    }

    private func navigationButton(_ title: String, symbol: String, destination: Int) -> some View {
        Button { select(destination) } label: {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular))
            .foregroundStyle(tab == destination ? FitTheme.dashboardAccent : FitTheme.textPrimary)
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
                NavigationLink("Edit profile & navigation") { ProfileEditor(store: container.profile, presentation: container.presentation) }
                    .accessibilityIdentifier("editProfileNavigation")
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

/// Adjacent controls share one native material sampling context.
private struct NavigationGlassGroup: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) { content }
        } else { content }
    }
}

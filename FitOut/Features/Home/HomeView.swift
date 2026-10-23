import SwiftUI

struct HomeView: View {
    let container: AppContainer
    @Binding var tab: Int
    @State private var showHealth = false
    @State private var showSettings = false
    var workout: TodayWorkoutState {
        var input = container.gym.homeInput()
        if let completed = container.workouts.history.first(where: { $0.status == .completed && Calendar.current.isDateInToday($0.startedAt) }) {
            input.completion = (completed.title, completed.completedSets.count, completed.duration(), completed.volumeKG)
        }
        return HomeStateResolver.workout(input)
    }
    var body: some View {
        List {
            Section {
                HStack {
                    Text(container.profile.draft.emoji).font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("Hello, \(container.profile.draft.trimmedName)").font(.title2.bold())
                        Text(Date.now, format: .dateTime.weekday(.wide).month().day()).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Today’s workout") { WorkoutStateContent(state: workout, openGym: { tab = 1 }, startWorkout: {
                if case .planned = workout, container.workouts.active == nil, let routine = container.gym.activeRoutine, let day = RoutineSchedule.day(in: routine, at: .now) {
                    container.workouts.start(day: day, routineID: routine.id, catalogue: container.gym.exercises)
                }
                tab = 1
            }) }
            Section("Set up your tracking") {
                Button("Set Up Workout Routine") { tab = 1 }
                Button("Nutrition targets (optional)") { tab = 2 }
                Button(container.health.hasRequested ? "Review Apple Health" : "Connect Apple Health (optional)") { tab = 3 }
            }
            Section("Nutrition and water") {
                Text("No food or water logged today.").foregroundStyle(.secondary)
                Button("Log Meal") { tab = 2 }
                Button("Add Water") { tab = 2 }
            }
            Section("Health") {
                Text("Health readings appear only when available from Apple Health. Manual tracking works without a connection.").foregroundStyle(.secondary)
                Button("Record Weight") { tab = 3 }
            }
            Section { Button("Try AI Coach") { tab = 4 } }
            NavigationLink("Settings") { FoundationSettings(container: container) }
        }.navigationTitle("Home")
            .toolbar { Button { showSettings = true } label: { Image(systemName: "gearshape").accessibilityLabel("Open Settings") } }
            .navigationDestination(isPresented: $showSettings) { FoundationSettings(container: container) }
            .task {
                if !container.defaults.bool(forKey: "health.explainer.seen") { showHealth = true }
            }
            .sheet(isPresented: $showHealth, onDismiss: markExplained) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "heart.fill").font(.largeTitle).foregroundStyle(FitTheme.orange)
                        Text("Connect Apple Health").font(.title.bold())
                        Text("With your permission, FitOut can read supported activity and health measurements. You choose each data type in the system sheet. No Apple Watch is required.")
                        Text("This is optional. You can connect later in Settings.").foregroundStyle(.secondary)
                        Button("Connect Apple Health") { markExplained(); showHealth = false; tab = 3; Task { await container.health.requestAccess() } }
                            .buttonStyle(.borderedProminent).disabled(!container.health.isAvailable)
                        Button("Not Now") { markExplained(); showHealth = false }.accessibilityIdentifier("dismissHealthExplainer")
                    }.padding(24)
                }.presentationDetents([.medium, .large])
            }
    }
    private func markExplained() { container.defaults.set(true, forKey: "health.explainer.seen") }
}

struct WorkoutStateContent: View {
    let state: TodayWorkoutState
    let openGym: () -> Void
    var startWorkout: (() -> Void)? = nil
    var body: some View {
        switch state {
        case .noRoutine:
            Text("Plan your workouts").font(.headline)
            Text("Create a weekly routine when you’re ready.")
        case .rest:
            Label("Rest Day", systemImage: "leaf")
            Text("Recovery is part of your schedule.")
            Button("View schedule", action: openGym)
        case .flexible:
            Text("Flexible day").font(.headline)
            Button("View schedule", action: openGym)
        case .planned(let title, let count, let minutes):
            Text(title).font(.headline)
            Text("\(count) exercises")
            if let minutes { Text("Target duration: \(minutes) min") }
            Button("Start Workout", action: startWorkout ?? openGym)
            Button("View or edit routine", action: openGym)
        case .completed(let title, let sets, let seconds, let volume):
            Label("Completed · \(title)", systemImage: "checkmark.circle")
            Text("\(sets) sets · \(Int(seconds / 60)) min")
            if volume > 0 { Text("\(volume.formatted()) kg·reps") }
            Button("View workout summary", action: openGym)
        }
    }
}

struct HealthConnectionView: View {
    @Bindable var service: HealthAccessService
    var body: some View {
        List {
            Section {
                Text(service.hasRequested ? "Apple Health setup requested" : "Connect Apple Health").font(.headline)
                Text("Read access is controlled in Apple Health. If measurements are missing, they may be unavailable or not shared. FitOut cannot tell whether read permission was denied.")
                if service.isAvailable {
                    Button(service.hasRequested ? "Review access" : "Connect Apple Health") { Task { await service.requestAccess() } }.disabled(service.isRequesting)
                } else { Text("Apple Health is unavailable in this device configuration.") }
                if service.isRequesting { ProgressView("Requesting access…") }
                if let error = service.error { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("Health")
    }
}

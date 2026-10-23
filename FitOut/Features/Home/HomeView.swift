import SwiftUI

struct HomeView: View {
    let container: AppContainer
    @Binding var tab: Int
    @State private var showHealth = false
    @State private var showSettings = false
    @State private var showWorkout = false
    @State private var newRoutine: Routine?
    private let accent = FitTheme.dashboardAccent

    private var weeklySessions: [WorkoutSession] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return container.workouts.history.filter { $0.status == .completed && week.contains($0.startedAt) && $0.startedAt <= .now }
    }

    private var completedCount: Int {
        weeklySessions.count
    }

    private var weeklyGoal: Int {
        if let routine = container.gym.activeRoutine {
            let workoutDays = routine.days.filter { $0.kind == .workout }.count
            if workoutDays > 0 { return workoutDays }
        }
        return 0
    }

    private var onTrackPercentage: Int {
        guard weeklyGoal > 0 else { return 0 }
        return min(100, Int(Double(completedCount) / Double(weeklyGoal) * 100))
    }

    var workout: TodayWorkoutState {
        var input = container.gym.homeInput()
        if let completed = container.workouts.history.first(where: { $0.status == .completed && Calendar.current.isDateInToday($0.startedAt) }) {
            input.completion = (completed.title, completed.completedSets.count, completed.duration(), completed.volumeKG)
        }
        return HomeStateResolver.workout(input)
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hi \(container.profile.draft.trimmedName),")
                        .font(.system(size: 28, weight: .semibold))
                        .lineLimit(2)
                    Text("Welcome!")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundStyle(accent)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.leading, 24)
                .padding(.trailing, 88)
                .padding(.top, 16)

                // Leave the athlete's full pose visible before the dashboard cards.
                Color.clear.frame(height: min(480, max(340, geometry.size.height * 0.56)))
                    .accessibilityHidden(true)

                // Hero Workout CTA Card: "Set up your workout routine"
                heroWorkoutCard
                    .padding(.horizontal, 20)

                // Workouts Weekly Tracker Card
                workoutsWeeklyCard
                    .padding(.horizontal, 20)

                // 2x2 Metrics Grid: Water Intake, Steps, Calories, Sleep
                metricsGrid
                    .padding(.horizontal, 20)
                Button { showSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .dashboardGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain).accessibilityLabel("Open Settings")
                .frame(maxWidth: .infinity)
                .padding(.top, 8).padding(.bottom, 32)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background { HomeBackdrop(contentMode: .fill) }
        }
        .foregroundStyle(.white)
        .tint(accent)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            FoundationSettings(container: container).toolbar(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showWorkout) {
            NavigationStack {
                ActiveWorkoutView(store: container.workouts, gym: container.gym, unit: container.profile.draft.weightUnit, defaults: container.defaults)
            }
        }
        .sheet(item: $newRoutine) { routine in
            RoutineEditor(store: container.gym, routine: routine)
        }
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
                    Button("Connect Apple Health") {
                        markExplained()
                        showHealth = false
                        tab = 3
                        Task { await container.health.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!container.health.isAvailable)
                    Button("Not Now") {
                        markExplained()
                        showHealth = false
                    }
                    .accessibilityIdentifier("dismissHealthExplainer")
                }
                .padding(24)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Hero Workout Card ("Set up your workout routine")
    private var heroWorkoutCard: some View {
        Button(action: openTodayWorkout) {
            HStack(spacing: 14) {
                // Circular dumbbell badge with glowing orange border and radial glow
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [FitTheme.orange.opacity(0.32), FitTheme.orange.opacity(0.06)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 26
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay {
                            Circle().stroke(FitTheme.orange.opacity(0.75), lineWidth: 1.3)
                        }

                    Image(systemName: "dumbbell")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(heroWorkoutTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(heroWorkoutSubtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(FitTheme.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Glowing circular orange CTA button with arrow
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.95, green: 0.22, blue: 0.05), Color(red: 0.78, green: 0.12, blue: 0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .dashboardGlass(in: RoundedRectangle(cornerRadius: 24), highlighted: true, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(heroWorkoutTitle). \(heroWorkoutSubtitle)")
    }

    private var heroWorkoutTitle: String {
        if let session = container.workouts.active { return session.title }
        switch workout {
        case .noRoutine: return "Set up your workout routine"
        case .rest: return "Rest day"
        case .flexible: return "Flexible workout"
        case .planned(let title, _, _): return title
        case .completed(let title, _, _, _): return "\(title) completed"
        }
    }

    private var heroWorkoutSubtitle: String {
        if let session = container.workouts.active {
            return "\(session.completedSets.count) sets logged · \(session.entries.count) exercises"
        }
        switch workout {
        case .noRoutine:
            return "Get a personalized plan based on your goals."
        case .rest:
            return "Take a breath. Recovery is part of the plan."
        case .flexible:
            return "Choose a quick session or enjoy a lighter day."
        case .planned(_, let count, let minutes):
            return "\(count) exercises" + (minutes.map { " · \($0) min" } ?? "")
        case .completed(_, let sets, let seconds, _):
            return "\(sets) sets · \(Int(seconds / 60)) min logged today"
        }
    }

    // MARK: - Workouts Weekly Tracker Card
    private var workoutsWeeklyCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header Row
            HStack {
                Text("Workouts")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                NavigationLink {
                    AnalyticsView(store: container.workouts, gym: container.gym, unit: container.profile.draft.weightUnit)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FitTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View workout analytics")
            }

            // Days of the Week Bubbles (Sunday to Saturday)
            HStack(spacing: 0) {
                ForEach(weekDaysData) { day in
                    VStack(spacing: 8) {
                        dayBubble(for: day.status)
                        Text(day.letter)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FitTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + ", " + day.description)
                }
            }

            // Bottom Stats Row
            HStack(alignment: .center, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(completedCount)")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text(weeklyGoal > 0 ? "/\(weeklyGoal)" : "")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FitTheme.textSecondary)
                    Text("Completed\nthis week")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(FitTheme.textSecondary)
                        .padding(.leading, 6)
                        .lineSpacing(2)
                }

                Spacer()

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(weeklyGoal > 0 ? "\(onTrackPercentage)%" : "—")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(weeklyGoal > 0 ? "Of weekly goal" : "No routine yet")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(FitTheme.textSecondary)
                }
                .frame(minWidth: 70, alignment: .leading)
            }
        }
        .padding(18)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 24))
    }

    private func dayBubble(for status: WeekDayStatus) -> some View {
        ZStack {
            switch status {
            case .completed:
                Circle()
                    .fill(Color(red: 0.14, green: 0.77, blue: 0.44))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

            case .rest:
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().stroke(Color.white.opacity(0.08), lineWidth: 1) }
                Image(systemName: "moon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.65))

            case .missed:
                Circle()
                    .fill(Color(red: 0.92, green: 0.26, blue: 0.21))
                    .frame(width: 34, height: 34)
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

            case .todayPlanned:
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().stroke(FitTheme.orange, lineWidth: 1.5) }
                Image(systemName: "dumbbell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FitTheme.orange)

            case .futurePlanned:
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().stroke(Color.white.opacity(0.15), lineWidth: 1) }
            case .noLog:
                Circle().fill(.white.opacity(0.05)).frame(width: 34, height: 34)
                Image(systemName: "minus").font(.system(size: 12)).foregroundStyle(FitTheme.textSecondary)
            case .inProgress:
                Circle().stroke(FitTheme.orange, lineWidth: 1.5).frame(width: 34, height: 34)
                Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(FitTheme.orange)
            }
        }
    }

    private var weekDaysData: [WeekDayItem] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [] }
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index, to: week.start) else { return nil }
            let label = WorkoutAnalytics.dayLabel(date, sessions: container.workouts.sessions,
                routine: container.gym.activeRoutine, calendar: calendar)
            let status: WeekDayStatus
            switch label {
            case "Completed": status = .completed
            case "Skipped", "Abandoned": status = .missed
            case "In progress": status = .inProgress
            case "Rest": status = .rest
            case "Planned": status = calendar.isDateInToday(date) ? .todayPlanned : .futurePlanned
            default: status = .noLog
            }
            let letter = calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return WeekDayItem(date: date, letter: letter, status: status, description: label)
        }
    }

    // MARK: - 2x2 Metrics Grid
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            metricCard(
                title: "Water Intake",
                symbol: "drop.fill",
                value: "—",
                targetUnit: "No logs yet",
                progress: 0,
                progressGradient: false,
                destinationTab: 2
            )

            metricCard(
                title: "Steps",
                symbol: "shoeprints.fill",
                value: "—",
                targetUnit: "No reading",
                progress: 0,
                progressGradient: false,
                destinationTab: 3
            )

            metricCard(
                title: "Calories",
                symbol: "flame.fill",
                value: "—",
                targetUnit: "No logs yet",
                progress: 0,
                progressGradient: false,
                destinationTab: 2
            )

            metricCard(
                title: "Sleep",
                symbol: "moon.fill",
                value: "—",
                targetUnit: "No reading",
                progress: 0,
                progressGradient: true,
                destinationTab: 3
            )
        }
    }

    private func metricCard(
        title: String,
        symbol: String,
        value: String,
        targetUnit: String,
        progress: Double,
        progressGradient: Bool,
        destinationTab: Int
    ) -> some View {
        Button {
            tab = destinationTab
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                // Top Row: Icon, Title, Chevron
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [FitTheme.orange.opacity(0.35), FitTheme.orange.opacity(0.04)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 18
                                )
                            )
                            .frame(width: 36, height: 36)
                            .overlay {
                                Circle().stroke(FitTheme.orange.opacity(0.7), lineWidth: 1.2)
                            }

                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                // Middle Value
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    if !targetUnit.isEmpty {
                        Text(targetUnit)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FitTheme.textSecondary)
                    }
                }

                // Bottom Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 7)

                        if progressGradient {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(red: 0.58, green: 0.45, blue: 0.98), Color(red: 0.45, green: 0.68, blue: 0.98)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, progress))), height: 7)
                        } else {
                            Capsule()
                                .fill(FitTheme.orange)
                                .frame(width: geo.size.width * CGFloat(min(1.0, max(0.0, progress))), height: 7)
                        }
                    }
                }
                .frame(height: 7)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardGlass(in: RoundedRectangle(cornerRadius: 22), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title): \(value)\(targetUnit)")
    }

    // MARK: - Actions
    private func startQuickWorkout() {
        if container.workouts.active != nil {
            showWorkout = true
        } else if container.workouts.start(catalogue: container.gym.exercises) {
            showWorkout = true
        }
    }

    private func openTodayWorkout() {
        if container.workouts.active != nil {
            showWorkout = true
            return
        }
        switch workout {
        case .noRoutine:
            newRoutine = RoutineTemplate.custom.make()
        case .rest:
            tab = 1
        case .flexible:
            startQuickWorkout()
        case .planned:
            if let routine = container.gym.activeRoutine,
               let day = RoutineSchedule.day(in: routine, at: .now),
               container.workouts.start(day: day, routineID: routine.id, catalogue: container.gym.exercises) {
                showWorkout = true
            }
        case .completed:
            tab = 1
        }
    }

    private func markExplained() {
        container.defaults.set(true, forKey: "health.explainer.seen")
    }
}

// MARK: - Types
enum WeekDayStatus {
    case completed
    case rest
    case missed
    case todayPlanned
    case futurePlanned
    case noLog
    case inProgress
}

struct WeekDayItem: Identifiable {
    var id: Date { date }
    let date: Date
    let letter: String
    let status: WeekDayStatus
    let description: String
}

// MARK: - Background
struct HomeBackdrop: View {
    var contentMode: ContentMode = .fit

    var body: some View {
        GeometryReader { geometry in
            Image("HomeAthlete")
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
                .overlay {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.42), location: 0),
                        .init(color: .clear, location: 0.18),
                        .init(color: .clear, location: 0.62),
                        .init(color: FitTheme.dashboardBackground.opacity(0.22), location: 0.82),
                        .init(color: FitTheme.dashboardBackground.opacity(0.70), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .background(FitTheme.dashboardBackground)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Health Connection View
struct HealthConnectionView: View {
    @Bindable var service: HealthAccessService
    var body: some View {
        List {
            Section {
                Text(service.hasRequested ? "Apple Health setup requested" : "Connect Apple Health").font(.headline)
                Text("Read access is controlled in Apple Health. If measurements are missing, they may be unavailable or not shared. FitOut cannot tell whether read permission was denied.")
                if service.isAvailable {
                    Button(service.hasRequested ? "Review access" : "Connect Apple Health") {
                        Task { await service.requestAccess() }
                    }
                    .disabled(service.isRequesting)
                } else {
                    Text("Apple Health is unavailable in this device configuration.")
                }
                if service.isRequesting {
                    ProgressView("Requesting access…")
                }
                if let error = service.error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Health")
    }
}

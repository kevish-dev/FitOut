import SwiftUI
import Combine

struct HomeView: View {
    let container: AppContainer
    @Binding var tab: Int
    @State private var showHealth = false
    @State private var showSettings = false
    @State private var showWorkout = false
    @State private var showWater = false
    @State private var newRoutine: Routine?
    @State private var creatingRoutine = false
    private var healthOverview: HealthOverview {
        let health = container.health.overview
        let local = container.hydration.state.localWater(at: .now)
        guard local > 0 else { return health }
        var buckets = health.waterMilliliters.buckets
        if buckets.count != 12 { buckets = Array(repeating: 0, count: 12) }
        for log in container.hydration.state.water where Calendar.current.isDateInToday(log.date) {
            buckets[Calendar.current.component(.hour, from: log.date) / 2] += Double(log.milliliters)
        }
        return HealthOverview(waterMilliliters: HealthMetricSeries(total: (health.waterMilliliters.total ?? 0) + Double(local), buckets: buckets, errorMessage: health.waterMilliliters.errorMessage),
                              steps: health.steps, activeCalories: health.activeCalories, sleepHours: health.sleepHours)
    }
    private var isLoadingHealth: Bool { container.health.isRefreshing }
    private var displayedHealthReadings: [HealthMetricSeries] {
        [healthOverview.waterMilliliters, healthOverview.steps, healthOverview.activeCalories]
    }
    private var displayedHealthErrors: [String] {
        [("Water", healthOverview.waterMilliliters), ("Steps", healthOverview.steps), ("Active calories", healthOverview.activeCalories)]
            .compactMap { name, series in series.errorMessage.map { "\(name): \($0)" } }
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var homeInsight: HomeWorkoutInsight?
    #if DEBUG
    @State private var showingRestartConfirmation = false
    @State private var restartError: String?
    #endif
    private let accent = FitTheme.dashboardAccent

    private var insightRequest: HomeInsightRequest {
        let available = scenePhase == .active && container.capabilities.currentCapabilities().foundationModels.isAvailable
        return HomeInsightRequest(isAvailable: available, candidates: available
            ? HomeInsightPolicy.candidates(sessions: container.workouts.history, routine: container.gym.activeRoutine,
                                           unit: container.profile.draft.weightUnit)
            : [])
    }

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
        let now = Date()
        let calendar = Calendar.current
        var input = container.gym.homeInput(at: now, calendar: calendar)
        if let routine = container.gym.activeRoutine,
           let day = RoutineSchedule.day(in: routine, at: now, calendar: calendar),
           day.kind == .workout,
           let completed = container.workouts.history.first(where: {
               $0.status == .completed && $0.routineID == routine.id &&
               calendar.isDate($0.startedAt, inSameDayAs: now)
           }) {
            input.completion = (day.title, completed.completedSets.count, completed.duration(), completed.volumeKG)
        }
        return HomeStateResolver.workout(input)
    }

    var body: some View {
        DashboardScroll(onRefresh: refreshHealthOverview) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hi \(container.profile.draft.trimmedName),")
                    .font(FitTheme.section(20))
                    .lineLimit(2)
                Text("Welcome!")
                    .font(FitTheme.hero(32))
                    .foregroundStyle(accent)
                    .accessibilityAddTraits(.isHeader)
            }
        } content: {
            // Hero Workout CTA Card: "Set up your workout routine"
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                heroWorkoutCard
                    .padding(.horizontal, FitTheme.pageInset)
            }

            streakCard
                .padding(.horizontal, FitTheme.pageInset)

            // Workouts Weekly Tracker Card
            workoutsWeeklyCard
                .padding(.horizontal, FitTheme.pageInset)

            TimelineView(.periodic(from: .now, by: 3600)) { timeline in
                volumeTrendCard(at: timeline.date)
                    .padding(.horizontal, FitTheme.pageInset)
            }

            if let insight = homeInsight, insightRequest.isAvailable,
               insightRequest.candidates.contains(insight) {
                insightCard(insight)
                    .padding(.horizontal, FitTheme.pageInset)
            }

            // A compact visual summary of readings shared from Apple Health.
            metricsGrid
                .padding(.horizontal, FitTheme.pageInset)
            Button { showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(FitTheme.medium(14))
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .dashboardGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.fitPlain).accessibilityLabel("Open Settings")
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            #if DEBUG
            Button { showingRestartConfirmation = true } label: {
                Label("Start Over (Testing)", systemImage: "arrow.counterclockwise")
                    .font(FitTheme.button(14))
                    .foregroundStyle(FitTheme.textPrimary.opacity(0.8))
                    .padding(.horizontal, 20).padding(.vertical, 14)
                    .dashboardGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.fitPlain)
            .accessibilityIdentifier("startOverTesting")
            .frame(maxWidth: .infinity)
            .confirmationDialog("Start over from onboarding?", isPresented: $showingRestartConfirmation, titleVisibility: .visible) {
                Button("Start Over", role: .destructive) {
                    do {
                        try container.profile.restartForTesting()
                        container.coach.newChat()
                        container.defaults.removeObject(forKey: "health.explainer.seen")
                    }
                    catch { restartError = error.localizedDescription }
                }
            } message: {
                Text("Your onboarding profile will reset. Workout history and routines stay saved.")
            }
            .alert("Unable to start over", isPresented: Binding(
                get: { restartError != nil },
                set: { if !$0 { restartError = nil } }
            )) {
                Button("OK", role: .cancel) { restartError = nil }
            } message: {
                Text(restartError ?? "")
            }
            #endif
        } backdrop: {
            HomeBackdrop(contentMode: .fill)
        }
        .foregroundStyle(FitTheme.textPrimary)
        .tint(accent)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showSettings) {
            FoundationSettings(container: container).toolbar(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showWorkout) {
            NavigationStack {
                QuickWorkoutFlow(store: container.workouts, gym: container.gym, unit: container.profile.draft.weightUnit, defaults: container.defaults)
            }
        }
        .sheet(isPresented: $showWater) {
            NavigationStack { HydrationView(store: container.hydration, health: container.health, reminders: container.hydrationReminders).toolbar { Button("Close") { showWater = false } } }
        }
        .sheet(item: $newRoutine) { routine in
            RoutineEditor(store: container.gym, routine: routine, unit: container.profile.draft.weightUnit)
        }
        .sheet(isPresented: $creatingRoutine) {
            RoutineCreationSheet(store: container.gym, unit: container.profile.draft.weightUnit)
        }
        .task {
            if !container.defaults.bool(forKey: "health.explainer.seen") { showHealth = true }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await refreshHealthOverview() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            if scenePhase == .active { Task { await refreshHealthOverview() } }
        }
        .task(id: insightRequest) {
            let request = insightRequest
            homeInsight = nil
            let result = await HomeInsightEngine.insight(for: request)
            guard !Task.isCancelled, request == insightRequest else { return }
            homeInsight = result
        }
        .sheet(isPresented: $showHealth, onDismiss: markExplained) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "heart.fill").font(.largeTitle).foregroundStyle(FitTheme.orange)
                    Text("Connect Apple Health").font(FitTheme.display(24))
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

    // MARK: - Workout preview
    private var heroWorkoutCard: some View {
        let state = GymLandingState.today(routine: container.gym.activeRoutine,
                                          sessions: container.workouts.sessions)
        return Button {
            if container.workouts.active != nil { showWorkout = true }
            else {
                switch state {
                case .rest, .unassigned, .completed: tab = 1
                default: openTodayWorkout()
                }
            }
        } label: {
            DashboardWorkoutPreview(state: state, routine: container.gym.activeRoutine,
                                    hasDraft: container.gym.resumableDraft != nil)
        }
        .buttonStyle(RoutineEditorPressStyle())
        .accessibilityIdentifier("homeTodayWorkout")
    }

    // MARK: - Daily Workout Streak
    private var streakCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let streak = container.streaks.snapshot(sessions: container.workouts.history, now: timeline.date)
            GeometryReader { geometry in
                let narrow = geometry.size.width < 320
                let compact = geometry.size.width < 380
                let markerSize: CGFloat = narrow ? 13 : compact ? 19 : 22
                let leftWidth: CGFloat = narrow ? 70 : compact ? 88 : 104
                let rightWidth: CGFloat = narrow ? 48 : compact ? 54 : 64
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Streak")
                            .font(FitTheme.section(narrow ? 13 : compact ? 15 : 16))
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(streak.consecutiveDays)")
                                .font(FitTheme.metric(streak.consecutiveDays >= 100 ? 24 : streak.consecutiveDays >= 10 ? 29 : narrow ? 31 : compact ? 36 : 39))
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: streak.consecutiveDays)
                                .foregroundStyle(FitTheme.textPrimary)
                            Text(streak.consecutiveDays == 1 ? "Day" : "Days")
                                .font(FitTheme.strong(narrow ? 10 : compact ? 12 : 13))
                                .foregroundStyle(accent)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                    .frame(width: leftWidth, height: 68, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(streak.consecutiveDays) day workout streak")
                    .accessibilityHint("Planned rest days preserve your streak without adding a workout day.")

                    streakDivider(color: FitTheme.textPrimary.opacity(0.15))

                    HStack(spacing: 0) {
                        ForEach(0..<streak.weekDays.count, id: \.self) { index in
                            let day = streak.weekDays[index]
                            VStack(spacing: 8) {
                                Text(["S", "M", "T", "W", "T", "F", "S"][index])
                                    .font(FitTheme.medium(narrow ? 9 : compact ? 10 : 11))
                                    .foregroundStyle(FitTheme.textSecondary)
                                Circle()
                                    .fill(day.isCompleted ? accent : FitTheme.textPrimary.opacity(0.04))
                                    .frame(width: markerSize, height: markerSize)
                                    .overlay {
                                        Circle().stroke(day.isCompleted ? accent : FitTheme.textPrimary.opacity(0.25), lineWidth: 1.5)
                                    }
                                    .overlay {
                                        if day.isCompleted || day.isRestDay {
                                            Image(systemName: day.isCompleted ? "checkmark" : "moon.fill")
                                                .font(.system(size: narrow ? 8 : compact ? 10 : 11, weight: .bold))
                                                .foregroundStyle(day.isCompleted ? FitTheme.textPrimary : FitTheme.textSecondary)
                                        }
                                    }
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + ", " +
                                (day.isCompleted ? "workout completed" : day.isRestDay ? "planned rest day, streak protected" : day.date > timeline.date ? "upcoming" : "no completed workout"))
                        }
                    }
                    .frame(maxWidth: .infinity)

                    streakDivider(color: FitTheme.textPrimary.opacity(0.15))

                    VStack(alignment: .center, spacing: 1) {
                        Text("\(streak.completedDaysThisWeek)/7")
                            .font(FitTheme.metric(narrow ? 18 : compact ? 21 : 23))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("This Week")
                            .font(FitTheme.medium(narrow ? 8 : compact ? 10 : 11))
                            .foregroundStyle(FitTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(width: rightWidth)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(streak.completedDaysThisWeek) of 7 workout days completed this week")
                }
                .padding(.horizontal, FitTheme.cardInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(FitTheme.surface)
                        .overlay(alignment: .leading) {
                            Image(systemName: "flame")
                                .font(.system(size: 76, weight: .ultraLight))
                                .foregroundStyle(FitTheme.textPrimary.opacity(0.035))
                                .frame(width: compact ? 108 : 130, height: 96)
                                .clipped()
                                .offset(x: compact ? 54 : 65, y: 10)
                                .accessibilityHidden(true)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(FitTheme.textPrimary.opacity(0.14), lineWidth: 1)
                }
            }
            .frame(height: 96)
            .accessibilityIdentifier("homeWorkoutStreak")
        }
    }

    private func streakDivider(color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 1, height: 62)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    // MARK: - Workouts Weekly Tracker Card
    private var workoutsWeeklyCard: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            // Header Row
            HStack {
                Text("Workouts")
                    .font(FitTheme.section())
                    .foregroundStyle(FitTheme.textPrimary)

                Spacer()

                NavigationLink {
                    AnalyticsView(store: container.workouts, gym: container.gym, unit: container.profile.draft.weightUnit)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FitTheme.textSecondary)
                }
                .buttonStyle(.fitPlain)
                .accessibilityLabel("View workout analytics")
            }

            // Days of the Week Bubbles (Sunday to Saturday)
            HStack(spacing: 0) {
                ForEach(weekDaysData) { day in
                    VStack(spacing: 8) {
                        dayBubble(for: day.status)
                        Text(day.letter)
                            .font(FitTheme.medium(12))
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
                        .font(FitTheme.metric(26))
                        .foregroundStyle(FitTheme.textPrimary)
                    Text(weeklyGoal > 0 ? "/\(weeklyGoal)" : "")
                        .font(FitTheme.medium(18))
                        .foregroundStyle(FitTheme.textSecondary)
                    Text("Completed\nthis week")
                        .font(FitTheme.body(11))
                        .foregroundStyle(FitTheme.textSecondary)
                        .padding(.leading, 6)
                        .lineSpacing(2)
                }

                Spacer()

                Rectangle()
                    .fill(FitTheme.textPrimary.opacity(0.12))
                    .frame(width: 1, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(weeklyGoal > 0 ? "\(onTrackPercentage)%" : "—")
                        .font(FitTheme.metric(18))
                        .foregroundStyle(FitTheme.textPrimary)
                    Text(weeklyGoal > 0 ? "Of weekly goal" : "No routine yet")
                        .font(FitTheme.body(12))
                        .foregroundStyle(FitTheme.textSecondary)
                }
                .frame(minWidth: 70, alignment: .leading)
            }
        }
        .padding(FitTheme.cardInset)
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
                    .foregroundStyle(FitTheme.textPrimary)

            case .rest:
                Circle()
                    .fill(FitTheme.textPrimary.opacity(0.06))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().stroke(FitTheme.textPrimary.opacity(0.08), lineWidth: 1) }
                Image(systemName: "moon.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(FitTheme.textPrimary.opacity(0.65))

            case .missed:
                Circle()
                    .fill(Color(red: 0.92, green: 0.26, blue: 0.21))
                    .frame(width: 34, height: 34)
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FitTheme.textPrimary)

            case .todayPlanned:
                Circle()
                    .fill(FitTheme.textPrimary.opacity(0.08))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().stroke(FitTheme.orange, lineWidth: 1.5) }
                Image(systemName: "dumbbell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FitTheme.orange)

            case .futurePlanned:
                Circle()
                    .fill(FitTheme.textPrimary.opacity(0.05))
                    .frame(width: 34, height: 34)
                    .overlay { Circle().stroke(FitTheme.textPrimary.opacity(0.15), lineWidth: 1) }
            case .noLog:
                Circle().fill(FitTheme.textPrimary.opacity(0.05)).frame(width: 34, height: 34)
                Image(systemName: "minus").font(.system(size: 12)).foregroundStyle(FitTheme.textSecondary)
            case .inProgress:
                Circle().stroke(FitTheme.orange, lineWidth: 1.5).frame(width: 34, height: 34)
                Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(FitTheme.orange)
            }
        }
    }

    // MARK: - Workout Volume Progression
    private func volumeTrendCard(at date: Date) -> some View {
        let trend = WorkoutAnalytics.recentWeeklyVolume(container.workouts.history, now: date)
        let unit = container.profile.draft.weightUnit
        return VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TRAINING / 6 WEEKS")
                        .font(FitTheme.medium(11)).tracking(1.8)
                        .foregroundStyle(accent)
                    Text("Workout volume")
                        .font(FitTheme.section(20))
                }
                Spacer()
                NavigationLink {
                    AnalyticsView(store: container.workouts, gym: container.gym, unit: unit)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FitTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(FitTheme.textPrimary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.fitPlain)
                .accessibilityLabel("View workout volume analytics")
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("THIS WEEK SO FAR")
                    .font(FitTheme.medium(11)).tracking(1.2)
                    .foregroundStyle(FitTheme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trend.hasVolume ? unit.display(trend.currentWeekKG).formatted(.number.precision(.fractionLength(0))) : "—")
                        .font(FitTheme.metric(30))
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .contentTransition(.numericText())
                        .animation(FitMotion.change(reduceMotion: reduceMotion), value: trend.currentWeekKG)
                    Text("\(unit.rawValue)·reps")
                        .font(FitTheme.medium(12))
                        .foregroundStyle(FitTheme.textSecondary)
                }
            }

            WeeklyVolumeBars(trend: trend, unit: unit)

            if trend.hasVolume {
                HStack {
                    Text("Last week")
                        .foregroundStyle(FitTheme.textSecondary)
                    Spacer()
                    Text("\(unit.display(trend.previousWeekKG).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue)·reps")
                        .foregroundStyle(FitTheme.textPrimary)
                }
                .font(FitTheme.medium(12))
                Text("Completed weighted sets · load × reps")
                    .font(FitTheme.body(11))
                    .foregroundStyle(FitTheme.textSecondary)
            } else {
                Button { tab = 1 } label: {
                    HStack(spacing: 8) {
                        Text("Log a weighted workout to start your trend")
                        Image(systemName: "arrow.right")
                    }
                    .font(FitTheme.button(12))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.fitPlain)
            }
        }
        .padding(FitTheme.cardInset)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("homeWorkoutVolume")
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

    private func insightCard(_ insight: HomeWorkoutInsight) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Workout insight", systemImage: "sparkles")
                .font(FitTheme.section(16))
                .foregroundStyle(accent)
            Text(insight.text)
                .font(FitTheme.body(14))
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                AnalyticsView(store: container.workouts, gym: container.gym,
                              unit: container.profile.draft.weightUnit, initialExerciseID: insight.exerciseID)
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                HStack(spacing: 8) {
                    Text("Review progression")
                    Image(systemName: "arrow.right")
                }
                .font(FitTheme.button(13))
                .foregroundStyle(accent)
                .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.fitPlain)
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitSurface(radius: 20)
        .accessibilityIdentifier("homeWorkoutInsight")
    }

    // MARK: - Daily Health Overview
    private var metricsGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("HEALTH / TRAINING")
                        .font(FitTheme.medium(11)).tracking(1.8)
                        .foregroundStyle(accent)
                    Text("Activity overview")
                        .font(FitTheme.section(20))
                }
                Spacer()
                Button { tab = 3 } label: {
                    HStack(spacing: 5) {
                        Text("Health data")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(FitTheme.medium(12))
                    .foregroundStyle(FitTheme.textSecondary)
                }
                .buttonStyle(.fitPlain)
                .accessibilityLabel("Open Apple Health connection")
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: FitTheme.sectionSpacing), GridItem(.flexible(), spacing: FitTheme.sectionSpacing)], spacing: FitTheme.sectionSpacing) {
                Button { showWater = true } label: {
                    HealthOverviewTile(kind: .water, series: healthOverview.waterMilliliters, isLoading: isLoadingHealth, waterUnit: container.hydration.state.waterDisplayUnit)
                }.buttonStyle(.fitPlain).accessibilityHint("Opens water logging")
                HealthOverviewTile(kind: .steps, series: healthOverview.steps, isLoading: isLoadingHealth)
                HealthOverviewTile(kind: .calories, series: healthOverview.activeCalories, isLoading: isLoadingHealth)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HealthOverviewTile(kind: .workoutTime,
                        series: HomeStateResolver.weeklyWorkoutTime(container.workouts.sessions, now: context.date), isLoading: false)
                }.accessibilityIdentifier("homeWeeklyWorkoutTime")
            }

            if !container.health.hasRequested && !displayedHealthReadings.contains(where: { $0.total != nil }) {
                Button { tab = 3 } label: {
                    Label("Connect Apple Health to see your daily readings", systemImage: "heart.text.square")
                        .font(FitTheme.medium(12))
                        .foregroundStyle(FitTheme.textPrimary.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.fitPlain)
            } else if !isLoadingHealth && displayedHealthErrors.isEmpty && (healthOverview.steps.total == nil || healthOverview.activeCalories.total == nil) {
                Text("Missing activity readings? Review FitOut’s Steps and Active Energy access in Apple Health. Calories here means active energy burned, not food intake.")
                    .font(FitTheme.body(12))
                    .foregroundStyle(FitTheme.textSecondary)
            } else if isLoadingHealth {
                Text("Updating readings…")
                    .font(FitTheme.body(12))
                    .foregroundStyle(FitTheme.textSecondary)
            }
            if !isLoadingHealth {
                ForEach(displayedHealthErrors, id: \.self) { message in
                    Text(message).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
            }
        }
    }

    private func refreshHealthOverview() async {
        await container.health.refreshOverview()
    }

    // MARK: - Actions
    private func startQuickWorkout() { showWorkout = true }

    private func openTodayWorkout() {
        if case .noRoutine = workout {
            if let routine = container.gym.activeRoutine ?? container.gym.resumableDraft?.routine { newRoutine = routine }
            else { creatingRoutine = true }
            return
        }
        if container.workouts.active != nil {
            showWorkout = true
            return
        }
        switch workout {
        case .noRoutine:
            break
        case .rest:
            tab = 1
        case .flexible:
            startQuickWorkout()
        case .planned:
            if let routine = container.gym.activeRoutine,
               let day = RoutineSchedule.day(in: routine, at: .now) {
                if day.exercises.isEmpty { newRoutine = routine }
                else if container.workouts.start(day: day, routineID: routine.id, catalogue: container.gym.exercises) { showWorkout = true }
            }
        case .completed:
            tab = 1
        }
    }

    private func markExplained() {
        container.defaults.set(true, forKey: "health.explainer.seen")
    }
}

private struct WeeklyVolumeBars: View {
    let trend: WeeklyVolumeTrend
    let unit: WeightUnit

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(trend.weeks) { week in
                VStack(spacing: 7) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(FitTheme.textPrimary.opacity(0.06))
                            .frame(height: 68)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(week.isCurrent ? FitTheme.dashboardAccent : FitTheme.textPrimary.opacity(0.36))
                            .frame(height: week.volumeKG > 0
                                   ? max(5, CGFloat(week.volumeKG / max(1, trend.peakKG)) * 68)
                                   : 2)
                    }
                    Text(week.isCurrent ? "NOW" : week.start.formatted(.dateTime.month(.abbreviated).day()))
                        .font(FitTheme.medium(9))
                        .foregroundStyle(week.isCurrent ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Week of \(week.start.formatted(date: .abbreviated, time: .omitted)), \(unit.display(week.volumeKG).formatted(.number.precision(.fractionLength(0)))) \(unit.rawValue) times repetitions")
            }
        }
        .frame(height: 93, alignment: .bottom)
        .accessibilityLabel("Six week workout volume trend")
    }
}

private enum HomeMetricKind: Equatable {
    case water, steps, calories, workoutTime

    var title: String {
        switch self {
        case .water: "Water intake"
        case .steps: "Steps"
        case .calories: "Active calories"
        case .workoutTime: "Workout time"
        }
    }

    var context: String {
        switch self {
        case .water: "LOGGED TODAY"
        case .steps: "WALKED TODAY"
        case .calories: "BURNED TODAY"
        case .workoutTime: "THIS WEEK"
        }
    }

    var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .steps: "figure.walk"
        case .calories: "flame.fill"
        case .workoutTime: "timer"
        }
    }

    var tint: Color {
        switch self {
        case .water: Color(red: 0.37, green: 0.72, blue: 0.91)
        case .steps: FitTheme.dashboardAccent
        case .calories: Color(red: 1, green: 0.63, blue: 0.29)
        case .workoutTime: Color(red: 0.72, green: 0.75, blue: 0.77)
        }
    }

    func formattedValue(_ total: Double?) -> (value: String, unit: String) {
        guard let total else { return ("—", "") }
        switch self {
        case .water:
            return ((total / 1_000).formatted(.number.precision(.fractionLength(1))), "L")
        case .steps:
            return (Int(total.rounded()).formatted(), "steps")
        case .calories:
            return (Int(total.rounded()).formatted(), "kcal")
        case .workoutTime:
            let minutes = Int((total * 60).rounded(.down))
            return (total > 0 && minutes == 0 ? "<1m" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m", "")
        }
    }
}

private struct HealthOverviewTile: View {
    let kind: HomeMetricKind
    let series: HealthMetricSeries
    let isLoading: Bool
    var waterUnit: String? = nil

    private var reading: (value: String, unit: String) {
        if kind == .water, waterUnit == "ml", let total = series.total { return (Int(total.rounded()).formatted(), "ml") }
        return kind.formattedValue(series.total)
    }
    private var peak: Double { max(1, series.buckets.max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(kind.tint)
                    .frame(width: 36, height: 36)
                    .background(kind.tint.opacity(0.12), in: Circle())
                Spacer()
                Text(kind == .workoutTime ? "WEEK" : "2H")
                    .font(FitTheme.medium(10))
                    .foregroundStyle(FitTheme.textSecondary)
            }

            Text(kind.title)
                .font(FitTheme.section(15))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            visualization
                .frame(height: 50)
                .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.value)
                    .font(FitTheme.metric(kind == .workoutTime ? 19 : 22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !reading.unit.isEmpty {
                    Text(reading.unit)
                        .font(FitTheme.medium(11))
                        .foregroundStyle(FitTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Text(isLoading && series.total == nil ? "UPDATING…" : series.errorMessage != nil ? "COULDN’T LOAD" : series.total == nil ? "NO READING YET" : kind.context)
                .font(FitTheme.medium(10))
                .tracking(0.7)
                .foregroundStyle(FitTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, minHeight: 204, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 23)
                .fill(FitTheme.surface.opacity(0.9))
                .overlay(alignment: .topTrailing) {
                    Circle().fill(kind.tint.opacity(0.10)).frame(width: 88, height: 88)
                        .blur(radius: 30).offset(x: 10, y: -14)
                }
                .clipShape(RoundedRectangle(cornerRadius: 23))
        }
        .overlay { RoundedRectangle(cornerRadius: 23).stroke(FitTheme.textPrimary.opacity(0.10), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.title), \(series.errorMessage != nil ? "could not load reading" : series.total == nil ? "no reading yet" : "\(reading.value) \(reading.unit), \(kind.context.lowercased())")")
    }

    @ViewBuilder private var visualization: some View {
        switch kind {
        case .water:
            HStack(alignment: .bottom, spacing: 7) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(series.total == nil ? kind.tint.opacity(0.25) : kind.tint)
                    .frame(width: 32)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(series.buckets.indices, id: \.self) { index in
                        let level = series.buckets[index]
                        Circle()
                            .fill(level > 0 ? kind.tint : kind.tint.opacity(0.18))
                            .frame(maxWidth: .infinity)
                            .frame(height: level > 0 ? 5 + CGFloat(level / peak) * 12 : 4)
                    }
                }
                .frame(height: 32, alignment: .bottom)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .steps:
            GeometryReader { geometry in
                let values = series.buckets
                let width = max(1, geometry.size.width - 6)
                let height = max(1, geometry.size.height - 10)
                Path { path in
                    for index in values.indices {
                        let x = 3 + CGFloat(index) * width / CGFloat(max(1, values.count - 1))
                        let y = height + 5 - CGFloat(values[index] / peak) * height
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(kind.tint.opacity(series.total == nil ? 0.25 : 0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round,
                                           dash: series.total == nil ? [3, 5] : []))
            }
        case .calories:
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(series.buckets.indices, id: \.self) { index in
                    let level = series.buckets[index]
                    Capsule()
                        .fill(level > 0 ? kind.tint : kind.tint.opacity(0.14))
                        .frame(maxWidth: .infinity)
                        .frame(height: level > 0 ? 7 + CGFloat(level / peak) * 36 : 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        case .workoutTime:
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(series.buckets.indices, id: \.self) { index in
                    let duration = series.buckets[index]
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(kind.tint.opacity(duration > 0 ? 0.85 : 0.15))
                            .frame(height: duration > 0 ? 5 + CGFloat(duration / peak) * 29 : 3)
                        Text(String(Calendar.current.veryShortWeekdaySymbols[(Calendar.current.firstWeekday - 1 + index) % 7]))
                            .font(FitTheme.medium(8)).foregroundStyle(FitTheme.textSecondary)
                    }.frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
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
    @Environment(\.colorScheme) private var scheme
    var assetName = "HomeAthlete"
    var contentMode: ContentMode = .fit

    var body: some View {
        GeometryReader { geometry in
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
                .overlay { if scheme == .light { FitTheme.dashboardBackground.opacity(0.65) } }
                .overlay {
                    LinearGradient(stops: [
                        .init(color: FitTheme.dashboardBackground.opacity(0.42), location: 0),
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
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Text(service.overview.hasAnyReading ? "Apple Health readings available" : service.hasRequested ? "Apple Health setup requested" : "Connect Apple Health").font(FitTheme.section())
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
            if service.isAvailable {
                Section("Today’s activity readings") {
                    LabeledContent("Steps", value: reading(service.overview.steps, unit: "steps"))
                    LabeledContent("Active energy burned", value: reading(service.overview.activeCalories, unit: "kcal"))
                    Text("Active energy is calories burned through movement. Food calories and resting energy are separate readings.")
                        .font(FitTheme.body(12)).foregroundStyle(.secondary)
                    Button("Reload Health readings") { Task { await service.refreshOverview() } }
                        .disabled(service.isRefreshing || service.isRequesting)
                        .accessibilityIdentifier("reloadHealthReadings")
                    if service.isRefreshing { ProgressView("Reading Apple Health…") }
                    if let last = service.lastRefreshedAt {
                        Text("Last checked: \(last.formatted(date: .abbreviated, time: .standard))")
                            .font(FitTheme.body(12)).foregroundStyle(.secondary)
                    }
                    ForEach(service.overview.queryErrors, id: \.self) { message in
                        Text(message).font(FitTheme.body(12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Health")
        .refreshable { await service.refreshOverview() }
        .task(id: scenePhase) {
            if scenePhase == .active { await service.refreshOverview() }
        }
    }

    private func reading(_ series: HealthMetricSeries, unit: String) -> String {
        if series.errorMessage != nil { return "Couldn’t load" }
        guard let total = series.total else { return "No shared reading today" }
        return "\(total.formatted(.number.precision(.fractionLength(0)))) \(unit)"
    }
}

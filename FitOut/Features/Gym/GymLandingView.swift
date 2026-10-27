import SwiftUI
import Combine

struct GymView: View {
    @Bindable var store: GymStore
    let workouts: WorkoutStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @State private var navigation = GymNavigation()
    @State private var weekOffset = 0
    @State private var now = Date()
    @State private var visibleWeekday: Int? = RoutineSchedule.weekday(for: .now)
    @Environment(\.scenePhase) private var scenePhase

    private var today: GymTodayState { GymLandingState.today(routine: store.activeRoutine, sessions: workouts.sessions, now: now) }
    private var week: [GymWeekDay] { GymLandingState.week(routine: store.activeRoutine, sessions: workouts.sessions, offset: weekOffset, now: now) }
    private var weekSessions: [WorkoutSession] { GymLandingState.completedThisWeek(workouts.sessions, now: now) }
    private var hasHistory: Bool { !GymLandingState.completedSessions(workouts.sessions, through: now).isEmpty }
    private let accent = FitTheme.dashboardAccent

    var body: some View {
        DashboardScroll(onRefresh: refreshGym) {
            header
        } content: {
            VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                todayCard
                quickActions
                weeklyOverview
                trainingProgress
            }
            .padding(.horizontal, FitTheme.pageInset)
        } backdrop: {
            HomeBackdrop(assetName: "FitnessHero", contentMode: .fill)
        }
        .foregroundStyle(FitTheme.textPrimary)
        .tint(accent)
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: Binding(get: { navigation.destination }, set: { value in if value == nil { navigation.dismiss() } }), onDismiss: { now = .now }) { destination in
            switch destination {
            case .workout:
                NavigationStack { QuickWorkoutFlow(store: workouts, gym: store, unit: unit, defaults: defaults) }
            case let .routine(routine, weekday, stage):
                RoutineEditor(store: store, routine: routine, initialWeekday: weekday, initialStage: stage, unit: unit)
            case let .create(weekday, active):
                RoutineCreationSheet(store: store, unit: unit, initialWeekday: weekday, useAsActive: active)
            case .summary(let session):
                NavigationStack {
                    WorkoutSummary(session: session, unit: unit, history: workouts.history, store: workouts)
                        .navigationTitle("Workout summary")
                        .toolbar { Button("Close") { navigation.dismiss() } }
                }
            }
        }
        .alert("Could not update Gym", isPresented: Binding(get: { workouts.error != nil && navigation.destination == nil }, set: { if !$0 { workouts.error = nil } })) {
            Button("OK", role: .cancel) { workouts.error = nil }
        } message: { Text(workouts.error ?? "") }
        .onAppear { now = .now }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(FitTheme.section(20))
                .lineLimit(2)
            Text("Gym")
                .font(FitTheme.hero(32))
                .foregroundStyle(accent)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("gymTitle")
            Text("Your training. Your pace.")
                .font(FitTheme.body(14))
                .foregroundStyle(FitTheme.textPrimary.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            if let routine = store.activeRoutine {
                Label(routine.name, systemImage: "calendar")
                    .font(FitTheme.medium(12))
                    .lineLimit(2)
            } else {
                Text("BUILD A ROUTINE THAT FITS YOU")
                    .font(FitTheme.medium(10)).tracking(1.4)
                    .foregroundStyle(FitTheme.textPrimary.opacity(0.6))
            }
        }
    }

    private func refreshGym() async {
        do {
            try store.reload()
            try workouts.reload()
            store.error = nil
            workouts.error = nil
            now = .now
        } catch { workouts.error = error.localizedDescription }
    }

    private var todayCard: some View {
        VStack(spacing: 10) {
            Button(action: primaryAction) {
                DashboardWorkoutPreview(state: today, routine: store.activeRoutine,
                                        hasDraft: store.resumableDraft != nil)
            }
            .buttonStyle(RoutineEditorPressStyle())
            .accessibilityIdentifier(primaryIdentifier)
            if case .scheduled = today {
                Button { openPlan() } label: {
                    Label("View / edit plan", systemImage: "slider.horizontal.3")
                        .font(FitTheme.medium(13))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .dashboardGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
                }.buttonStyle(.fitPlain)
            }
        }
        .accessibilityIdentifier("gymTodayCard")
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            Text("Your training toolkit").font(FitTheme.section(19))
            Button { startWorkout() } label: { QuickWorkoutLaunchCard(active: workouts.active) }
                .buttonStyle(RoutineEditorPressStyle())
                .accessibilityLabel(workouts.active == nil ? "Start quick workout" : "Resume workout")
                .accessibilityIdentifier("startQuickWorkout")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FitTheme.sectionSpacing), GridItem(.flexible(), spacing: FitTheme.sectionSpacing)], spacing: FitTheme.sectionSpacing) {
                Button { openPlan(weekly: true) } label: { GymShortcut(title: "Weekly plan", detail: "Shape your week", symbol: "calendar") }
                    .accessibilityIdentifier("gymWeeklyPlan")
                NavigationLink {
                    MyRoutinesView(store: store, unit: unit).toolbar(.visible, for: .navigationBar)
                } label: { GymShortcut(title: "My routines", detail: "Edit or switch plans", symbol: "square.stack.3d.up") }
                .accessibilityIdentifier("gymMyRoutines")
                NavigationLink {
                    ExerciseLibrary(store: store).toolbar(.visible, for: .navigationBar)
                } label: { GymShortcut(title: "Exercises", detail: "Find your movements", symbol: "dumbbell") }
                .accessibilityIdentifier("gymExercises")
                NavigationLink {
                    WorkoutHistory(store: workouts, unit: unit).toolbar(.visible, for: .navigationBar)
                } label: { GymShortcut(title: "Workout history", detail: "Revisit your sessions", symbol: "clock.arrow.circlepath") }
                .accessibilityIdentifier("gymHistory")
            }
            .buttonStyle(.fitPlain)
        }
    }

    private var weeklyOverview: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack {
                Text("Your training week").font(FitTheme.section(19))
                Spacer(minLength: 4)
                Button { weekOffset = 0 } label: {
                    Text(weekOffset == 0 ? "This week" : "Today")
                        .font(FitTheme.medium(12)).foregroundStyle(accent)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 12)
                        .dashboardGlass(in: Capsule(), highlighted: weekOffset == 0, interactive: true)
                }.buttonStyle(.fitPlain)
                .accessibilityLabel("Show current week")
            }
            HStack(spacing: 8) {
                Button { weekOffset -= 1 } label: { weekArrow("chevron.left") }
                    .accessibilityLabel("Previous week")
                Spacer()
                if let first = week.first?.date, let last = week.last?.date {
                    Text("\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
                }
                Spacer()
                Button { weekOffset += 1 } label: { weekArrow("chevron.right") }
                    .accessibilityLabel("Next week")
            }.buttonStyle(.fitPlain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(week) { day in
                        Button { openDay(day) } label: { GymDayTile(day: day) }
                            .buttonStyle(.fitPlain)
                            .id(day.weekday)
                            .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.title), \(day.detail)")
                            .accessibilityHint(day.session != nil ? "Opens the logged workout." : "Opens this weekday in your repeating plan.")
                            .accessibilityIdentifier("gymDay-\(day.weekday)")
                    }
                }.scrollTargetLayout().padding(.vertical, 2)
            }
            .scrollPosition(id: $visibleWeekday, anchor: .center)
            .onChange(of: weekOffset) { _, offset in visibleWeekday = offset == 0 ? RoutineSchedule.weekday(for: now) : 0 }
            Text("Tap a day to view a log or edit its repeating plan.")
                .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
        }
    }

    private func weekArrow(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            .frame(width: 44, height: 44)
            .dashboardGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
    }

    private var trainingProgress: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack {
                Text("Training progress").font(FitTheme.section(19))
                Spacer(minLength: 8)
                NavigationLink {
                    AnalyticsView(store: workouts, gym: store, unit: unit).toolbar(.visible, for: .navigationBar)
                } label: {
                    Image(systemName: "arrow.up.right").frame(width: 44, height: 44)
                        .dashboardGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.fitPlain).foregroundStyle(accent)
                .accessibilityLabel("Analytics and calendar")
            }
            if hasHistory {
                VStack(alignment: .leading, spacing: 20) {
                    Text("THIS WEEK / LOGGED").font(FitTheme.medium(10)).tracking(1.5).foregroundStyle(accent)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) { progressFigures }
                        VStack(alignment: .leading, spacing: 20) { progressFigures }
                    }
                    Text("Volume counts completed working and drop sets. Warm-ups are excluded.")
                        .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }
                .padding(FitTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
                .dashboardGlass(in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("gymProgress")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 24)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your first session starts the story.").font(FitTheme.section(15))
                        Text("Finish a workout to see your logged volume, sets, and sessions here.")
                            .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                    }
                }
                .padding(FitTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
                .dashboardGlass(in: RoundedRectangle(cornerRadius: 22))
                .accessibilityIdentifier("gymProgressEmpty")
            }
        }
    }

    @ViewBuilder private var progressFigures: some View {
        progressFigure(weekSessions.count.formatted(), label: "Sessions", symbol: "checkmark.circle")
        progressFigure(unit.display(weekSessions.reduce(0) { $0 + $1.volumeKG }).formatted(.number.precision(.fractionLength(0))),
                       label: "\(unit.rawValue) · reps", symbol: "dumbbell")
        progressFigure(weekSessions.reduce(0) { $0 + $1.completedSets.count }.formatted(), label: "Sets logged", symbol: "square.stack")
    }

    private func progressFigure(_ value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(value).font(FitTheme.metric(20)).fixedSize()
            Text(label).font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryIdentifier: String {
        switch today {
        case .setup: "gymSetupRoutine"
        case .active: "resumeWorkout"
        case .scheduled: "gymStartWorkout"
        case .completed: "gymWorkoutSummary"
        default: "gymEditToday"
        }
    }

    private func primaryAction() {
        switch today {
        case .setup: openPlan()
        case .rest, .unassigned: openPlan(weekday: RoutineSchedule.weekday(for: now))
        case .needsExercises(let day): openPlan(weekday: day.weekday)
        case .scheduled(let day): startWorkout(day: day)
        case .active: navigation.present(.workout)
        case .completed(let session): navigation.present(.summary(session))
        }
    }

    private func openPlan(weekday: Int? = nil, weekly: Bool = false) {
        navigation.present(GymNavigation.plan(active: store.activeRoutine, draft: store.resumableDraft, weekday: weekday, weekly: weekly))
    }

    private func openDay(_ day: GymWeekDay) {
        if let session = day.session {
            navigation.present(session.isActive ? .workout : .summary(session))
        } else { openPlan(weekday: day.weekday) }
    }

    private func startWorkout(day: RoutineDay? = nil) {
        guard navigation.destination == nil else { return }
        if workouts.active != nil || day == nil { navigation.present(.workout); return }
        guard let day else { return }
        guard day.kind == .workout, !day.exercises.isEmpty else { openPlan(weekday: day.weekday); return }
        if workouts.start(day: day, routineID: store.activeRoutine?.id, catalogue: store.exercises) {
            navigation.present(.workout)
        }
    }

}

/// One photo-led workout preview shared by Home and Gym. All badges come from saved data.
struct DashboardWorkoutPreview: View {
    let state: GymTodayState
    let routine: Routine?
    var hasDraft = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { statusBadge; Spacer(minLength: 0); facts }
                VStack(alignment: .leading, spacing: 10) { statusBadge; facts }
            }
            Spacer(minLength: 72)
            VStack(alignment: .leading, spacing: 9) {
                Text(title).font(FitTheme.display(23))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(FitTheme.body(13))
                    .foregroundStyle(.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(actionTitle).font(FitTheme.button(13))
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(FitTheme.textPrimary)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .dashboardGlass(in: Capsule(), highlighted: true)
                .padding(.top, 3)
            }
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 340 : 280, alignment: .leading)
        .background {
            GeometryReader { geometry in
                Image("FitnessHero").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                    .clipped()
            }
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0),
                                       .init(color: .black.opacity(0.12), location: 0.3),
                                       .init(color: .black.opacity(0.82), location: 0.68),
                                       .init(color: .black.opacity(0.96), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(FitTheme.textPrimary.opacity(0.18), lineWidth: 1) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        Label(status, systemImage: statusSymbol)
            .font(FitTheme.medium(12))
            .foregroundStyle(FitTheme.dashboardAccent)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(FitTheme.surface.opacity(0.85), in: Capsule())
            .overlay { Capsule().strokeBorder(FitTheme.textPrimary.opacity(0.14), lineWidth: 1) }
    }

    private var facts: some View {
        VStack(alignment: .trailing, spacing: 7) {
            if let count = exerciseCount { fact("\(count) exercises", symbol: "dumbbell") }
            if let minutes = plannedMinutes { fact("\(minutes) min target", symbol: "clock") }
        }
    }
    private func fact(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(FitTheme.medium(11))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
    }
    private var title: String {
        switch state {
        case .scheduled(let day), .needsExercises(let day): day.title
        case .active(let session), .completed(let session): session.title
        case .setup: hasDraft ? "Finish your routine" : "Build your routine"
        case .rest: "Room to recover"
        case .unassigned: "Your next session"
        }
    }
    private var status: String {
        switch state {
        case .scheduled, .needsExercises: "Today’s workout"
        case .active(let session): session.status == .paused ? "Paused" : "In progress"
        case .completed: "Completed today"
        case .setup: hasDraft ? "Continue setup" : "Get started"
        case .rest: "Rest day"
        case .unassigned: "Weekly plan"
        }
    }
    private var statusSymbol: String {
        switch state {
        case .completed: "checkmark"
        case .active: "play.fill"
        case .rest: "moon"
        default: "calendar"
        }
    }
    private var detail: String {
        switch state {
        case .scheduled(let day):
            [routine?.name, RoutineSchedule.weekdays[day.weekday]].compactMap { $0 }.joined(separator: " · ")
        case .needsExercises: "Add exercises to complete this day’s plan."
        case .active(let session): "\(session.completedSets.count) sets saved · Continue where you left off."
        case .completed(let session): "\(session.completedSets.count) sets logged · \(Int(session.duration() / 60)) min trained"
        case .setup: hasDraft ? "Your draft is saved. Pick up where you left off." : "Choose your training days and the exercises you enjoy."
        case .rest: "Take time to recover. Your schedule is ready when you are."
        case .unassigned:
            if let start = routine?.startsOn, start > Date() {
                "Your plan starts \(start.formatted(date: .abbreviated, time: .omitted))."
            } else { "Choose a day in your plan or train freestyle." }
        }
    }
    private var exerciseCount: Int? {
        switch state {
        case .scheduled(let day), .needsExercises(let day): day.exercises.count
        case .active(let session), .completed(let session): session.entries.filter { !$0.skipped }.count
        default: nil
        }
    }
    private var plannedMinutes: Int? {
        switch state {
        case .scheduled(let day), .needsExercises(let day): day.durationMinutes
        default: nil
        }
    }
    private var actionTitle: String {
        switch state {
        case .scheduled: "Start workout"
        case .needsExercises: "Add exercises"
        case .active: "Resume workout"
        case .completed: "View workout"
        case .setup: hasDraft ? "Continue routine" : "Set up routine"
        case .rest, .unassigned: "View weekly plan"
        }
    }
}

private struct GymShortcut: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(FitTheme.dashboardAccent)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(FitTheme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(FitTheme.section(14))
                Text(detail).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, minHeight: 115, alignment: .topLeading)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 19), interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 19))
    }
}

private struct GymDayTile: View {
    let day: GymWeekDay
    private var symbol: String {
        switch day.status {
        case .completed: "checkmark.circle.fill"
        case .active: "play.circle.fill"
        case .rest: "moon"
        case .planned: "dumbbell"
        case .unassigned: "plus"
        case .noLog: "minus"
        case .skipped: "forward"
        case .abandoned: "stop.circle"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(day.date, format: .dateTime.weekday(.abbreviated)).font(FitTheme.medium(11))
                Text(day.date, format: .dateTime.day()).font(FitTheme.section(14))
            }.foregroundStyle(day.isToday ? FitTheme.dashboardAccent : FitTheme.textSecondary)
            Image(systemName: symbol).font(.system(size: 21, weight: .medium))
                .foregroundStyle(day.status == .completed || day.isToday ? FitTheme.dashboardAccent : FitTheme.textPrimary.opacity(0.65))
                .padding(.vertical, 3)
            Text(day.title).font(FitTheme.section(12)).lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            Text(day.detail).font(FitTheme.body(10)).foregroundStyle(FitTheme.textSecondary).lineLimit(2)
        }
        .padding(12)
        .frame(width: 108)
        .frame(minHeight: 172, alignment: .topLeading)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 19), highlighted: day.isToday, interactive: true)
        .accessibilityElement(children: .ignore)
    }
}

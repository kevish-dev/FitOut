import SwiftUI
import Combine

private struct GymPlanEdit: Identifiable {
    let routine: Routine
    var weekday: Int? = nil
    var id: UUID { routine.id }
}

struct GymView: View {
    @Bindable var store: GymStore
    let workouts: WorkoutStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @State private var showingWorkout = false
    @State private var editing: GymPlanEdit?
    @State private var showingTemplates = false
    @State private var templateWeekday: Int?
    @State private var summary: WorkoutSession?
    @State private var weekOffset = 0
    @State private var now = Date()
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
        .foregroundStyle(.white)
        .tint(accent)
        .navigationTitle("Gym")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingWorkout, onDismiss: { now = .now }) {
            NavigationStack { ActiveWorkoutView(store: workouts, gym: store, unit: unit, defaults: defaults) }
        }
        .sheet(item: $editing, onDismiss: { now = .now }) { request in
            RoutineEditor(store: store, routine: request.routine, initialWeekday: request.weekday, unit: unit)
        }
        .sheet(item: $summary, onDismiss: { now = .now }) { session in
            NavigationStack {
                WorkoutSummary(session: session, unit: unit, history: workouts.history)
                    .navigationTitle("Workout summary")
                    .toolbar { Button("Close") { summary = nil } }
            }
        }
        .sheet(isPresented: $showingTemplates, onDismiss: { now = .now }) {
            RoutineCreationSheet(store: store, unit: unit, initialWeekday: templateWeekday)
        }
        .alert("Could not update Gym", isPresented: Binding(get: { workouts.error != nil && !showingWorkout }, set: { if !$0 { workouts.error = nil } })) {
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
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            if let routine = store.activeRoutine {
                Label(routine.name, systemImage: "calendar")
                    .font(FitTheme.medium(12))
                    .lineLimit(2)
            } else {
                Text("BUILD A ROUTINE THAT FITS YOU")
                    .font(FitTheme.medium(10)).tracking(1.4)
                    .foregroundStyle(.white.opacity(0.6))
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
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(cardEyebrow).font(FitTheme.medium(11)).tracking(1.5)
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: cardSymbol).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(cardTitle).font(FitTheme.section(25)).fixedSize(horizontal: false, vertical: true)
                cardDetail
            }
            Button(action: primaryAction) {
                HStack(spacing: 10) {
                    Image(systemName: primarySymbol)
                    Text(primaryTitle)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                }
                .font(FitTheme.button(15))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(accent, in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(primaryIdentifier)
            if case .scheduled = today {
                Button { openPlan() } label: {
                    Label("View / edit plan", systemImage: "slider.horizontal.3")
                        .font(FitTheme.medium(13))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .dashboardGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
                }.buttonStyle(.plain)
            }
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 24), highlighted: true)
        .accessibilityIdentifier("gymTodayCard")
    }

    @ViewBuilder private var cardDetail: some View {
        switch today {
        case .scheduled(let day):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { workoutFacts(day) }
                VStack(alignment: .leading, spacing: 8) { workoutFacts(day) }
            }
            if !day.muscles.isEmpty {
                Text(day.muscles.map(\.title).joined(separator: " · "))
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }
        case .active(let session):
            supportingText("\(session.completedSets.count) sets saved · \(session.status == .paused ? "Paused" : "In progress")")
        case .completed(let session):
            supportingText("\(session.completedSets.count) sets logged · \(Int(session.duration() / 60)) min")
        case .setup:
            supportingText(store.resumableDraft == nil
                ? "Choose your training days, add exercises, and make the plan your own."
                : "Your unfinished routine is saved. Continue from the day and step you left open.")
        case .needsExercises:
            supportingText("Your day is scheduled. Add the exercises you want to train before starting.")
        case .rest:
            supportingText("A rest day in \(store.activeRoutine?.name ?? "your routine"). Your next sessions are in the weekly plan.")
        case .unassigned:
            if let routine = store.activeRoutine, !routine.hasStarted(at: now), let start = routine.startsOn {
                supportingText("Your routine starts \(start.formatted(date: .abbreviated, time: .omitted)). You can review the plan or train freestyle below.")
            } else { supportingText("No workout assigned today. Plan a session or start a freestyle workout below.") }
        }
    }

    @ViewBuilder private func workoutFacts(_ day: RoutineDay) -> some View {
        Label("\(day.exercises.count) exercises", systemImage: "dumbbell")
            .font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
        if let minutes = day.durationMinutes {
            Label("\(minutes) min target", systemImage: "clock")
                .font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
        }
    }

    private func supportingText(_ text: String) -> some View {
        Text(text).font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack {
                Text("Your training toolkit").font(FitTheme.section(19))
                Spacer(minLength: 8)
                Button { startWorkout() } label: {
                    Image(systemName: workouts.active == nil ? "plus" : "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .dashboardGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workouts.active == nil ? "Start freestyle workout" : "Resume workout")
                .accessibilityIdentifier("startQuickWorkout")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: FitTheme.sectionSpacing), GridItem(.flexible(), spacing: FitTheme.sectionSpacing)], spacing: FitTheme.sectionSpacing) {
                Button { openPlan() } label: { GymShortcut(title: "Weekly plan", detail: "Shape your week", symbol: "calendar") }
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
            .buttonStyle(.plain)
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
                }.buttonStyle(.plain)
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
            }.buttonStyle(.plain)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(week) { day in
                            Button { openDay(day) } label: { GymDayTile(day: day) }
                                .buttonStyle(.plain)
                                .id(day.weekday)
                                .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.title), \(day.detail)")
                                .accessibilityHint(day.session != nil ? "Opens the logged workout." : "Opens this weekday in your repeating plan.")
                                .accessibilityIdentifier("gymDay-\(day.weekday)")
                        }
                    }.padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(RoutineSchedule.weekday(for: now), anchor: .center) }
                .onChange(of: weekOffset) { _, offset in proxy.scrollTo(offset == 0 ? RoutineSchedule.weekday(for: now) : 0, anchor: .leading) }
            }
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
                .buttonStyle(.plain).foregroundStyle(accent)
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

    private var cardEyebrow: String {
        switch today {
        case .setup: "YOUR NEXT CHAPTER"
        case .active: "PICK UP WHERE YOU LEFT OFF"
        case .completed: "TODAY / COMPLETED"
        case .rest: "TODAY / REST"
        case .unassigned: "TODAY / OPEN DAY"
        case .scheduled, .needsExercises: "TODAY’S WORKOUT"
        }
    }
    private var cardTitle: String {
        switch today {
        case .setup: store.resumableDraft == nil ? "Set up your workout routine" : "Finish your workout routine"
        case .active(let session), .completed(let session): session.title
        case .scheduled(let day), .needsExercises(let day): day.title
        case .rest: "Room to recover."
        case .unassigned: "Make today your own."
        }
    }
    private var cardSymbol: String {
        switch today {
        case .completed: "checkmark.circle"
        case .rest: "moon"
        case .setup, .unassigned: "calendar.badge.plus"
        default: "dumbbell"
        }
    }
    private var primaryTitle: String {
        switch today {
        case .setup: store.resumableDraft == nil ? "Set up routine" : "Continue routine"
        case .active: "Resume workout"
        case .completed: "View workout summary"
        case .needsExercises: "Add exercises"
        case .scheduled: "Start workout"
        case .rest, .unassigned: "View weekly plan"
        }
    }
    private var primarySymbol: String {
        switch today {
        case .active, .scheduled: "play.fill"
        case .completed: "checkmark"
        case .needsExercises: "plus"
        default: "calendar"
        }
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
        case .setup, .rest, .unassigned: openPlan()
        case .needsExercises(let day): openPlan(weekday: day.weekday)
        case .scheduled(let day): startWorkout(day: day)
        case .active: showingWorkout = true
        case .completed(let session): summary = session
        }
    }

    private func openPlan(weekday: Int? = nil) {
        if let routine = store.activeRoutine { editing = GymPlanEdit(routine: routine, weekday: weekday) }
        else if let draft = store.resumableDraft { editing = GymPlanEdit(routine: draft.routine, weekday: weekday) }
        else { templateWeekday = weekday; showingTemplates = true }
    }

    private func openDay(_ day: GymWeekDay) {
        if let session = day.session {
            if session.isActive { showingWorkout = true }
            else { summary = session }
        } else { openPlan(weekday: day.weekday) }
    }

    private func startWorkout(day: RoutineDay? = nil) {
        if workouts.active != nil { showingWorkout = true }
        else if workouts.start(day: day, routineID: day == nil ? nil : store.activeRoutine?.id, catalogue: store.exercises) {
            showingWorkout = true
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
                .foregroundStyle(day.status == .completed || day.isToday ? FitTheme.dashboardAccent : .white.opacity(0.65))
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

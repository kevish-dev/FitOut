import SwiftUI
import Combine

struct WorkoutsPanel: View {
    let store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @Binding var showing: Bool
    var body: some View {
        Section("Workouts") {
            if let active = store.active {
                Button("Resume \(active.title)") { showing = true }.accessibilityIdentifier("resumeWorkout")
                Text("\(active.completedSets.count) sets saved · \(active.status == .paused ? "Paused" : "In progress")").font(FitTheme.body(12))
            } else {
                Button("Start quick workout") { if store.start(catalogue: gym.exercises) { showing = true } }.accessibilityIdentifier("startQuickWorkout")
                if let routine = gym.activeRoutine, let day = RoutineSchedule.day(in: routine, at: .now), day.kind == .workout {
                    Button("Start \(day.title)") { if store.start(day: day, routineID: routine.id, catalogue: gym.exercises) { showing = true } }
                }
            }
            NavigationLink("Workout history") { WorkoutHistory(store: store, unit: unit) }
            NavigationLink("Analytics and calendar") { AnalyticsView(store: store, gym: gym, unit: unit) }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }

    }
}
struct ActiveWorkoutView: View {
    @Bindable var store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @State private var selecting = false
    @State private var replacing: UUID?
    @State private var finishing = false
    @State private var finished: WorkoutSession?
    @State private var expandedEntry: UUID?
    @State private var keyboardVisible = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let session = store.active {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                WorkoutSessionHero(session: session, unit: unit, now: context.date)
                            }
                            if session.entries.isEmpty {
                                WorkoutEmptyState()
                                Button("End session") { finishing = true }
                                    .font(FitTheme.medium(13)).frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityIdentifier("finishWorkout")
                            } else {
                                HStack {
                                    Text("Your exercises").font(FitTheme.section(18))
                                    Spacer()
                                    Text("\(session.remainingSetCount) sets remaining").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                                }
                                ForEach(session.entries) { entry in
                                    WorkoutExerciseCard(entry: entry,
                                        expanded: Binding(get: { expandedEntry == entry.id }, set: { dismissKeyboard(); expandedEntry = $0 ? entry.id : nil }),
                                        unit: unit, canComplete: session.status == .inProgress,
                                        binding: { setBinding(entry.id, $0) }, complete: { toggleSet(entry.id, $0) },
                                        deleteSet: { deleteSet(entry.id, $0) }, addSet: { addSet(entry.id) },
                                        notes: Binding(get: { store.active?.entries.first { $0.id == entry.id }?.notes ?? "" }, set: { value in changeEntry(entry.id) { $0.notes = value } }),
                                        replace: { dismissKeyboard(); replacing = entry.id; selecting = true },
                                        toggleSkip: { dismissKeyboard(); changeEntry(entry.id) { $0.skipped.toggle() } })
                                        .id(entry.id)
                                }
                            }
                            DisclosureGroup("Session notes") {
                                TextField("How did this workout feel?", text: Binding(get: { store.active?.notes ?? "" }, set: { value in store.update { $0.notes = value } }), axis: .vertical)
                                    .font(FitTheme.body(14)).padding(.top, 10)
                            }.font(FitTheme.medium(13)).routinePanel()
                        }
                        .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .onChange(of: expandedEntry) { _, id in
                        if let id { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) } }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { footer(session) }
                .onAppear { expandFirstEntry(session) }
            } else if let finished {
                WorkoutSummary(session: finished, unit: unit, history: store.history)
            } else {
                ContentUnavailableView("No active workout", systemImage: "dumbbell", description: Text("Your ended sessions are in workout history."))
            }
        }
        .background(FitTheme.dashboardBackground).foregroundStyle(.white).tint(FitTheme.dashboardAccent)
        .navigationTitle(finished == nil ? "Workout" : "Workout summary").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let session = store.active {
                    Button {
                        dismissKeyboard()
                        if session.status == .paused { store.resume() } else { store.pause() }
                    } label: {
                        Label(session.status == .paused ? "Resume" : "Pause", systemImage: session.status == .paused ? "play.fill" : "pause")
                    }.accessibilityIdentifier("pauseResumeWorkout")
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Close") { dismissKeyboard(); dismiss() } }
        }
        .presentationDragIndicator(.visible).presentationCornerRadius(30).preferredColorScheme(.dark)
        .sheet(isPresented: $selecting) {
            NavigationStack {
                ExerciseBrowser(store: gym, title: replacing == nil ? "Add exercises" : "Replace exercise",
                    mode: replacing == nil ? .multiple : .single) { exercises in
                        if let replacing, let exercise = exercises.first {
                            let index = store.active?.entries.firstIndex { $0.id == replacing }
                            store.replace(entryID: replacing, with: exercise)
                            if let index, let entries = store.active?.entries, entries.indices.contains(index) { expandedEntry = entries[index].id }
                        }
                        else if store.add(exercises) { expandedEntry = store.active?.entries.suffix(exercises.count).first?.id }
                        selecting = false
                    }
            }
        }
        .confirmationDialog("End this workout", isPresented: $finishing, titleVisibility: .visible) {
            Button("Complete workout") { finish(.completed) }.disabled(store.active?.completedSets.isEmpty != false)
            Button("Mark skipped") { finish(.skipped) }
            Button("Abandon workout", role: .destructive) { finish(.abandoned) }
        } message: {
            Text(store.active?.completedSets.isEmpty == true ? "No sets logged yet. You can keep training or mark this session skipped." : "Your logged sets and notes will be kept in workout history.")
        }
        .alert("Workout could not be updated", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onReceive(timer) { date in
            if let session = store.active, session.status == .inProgress, let deadline = session.restUntil, deadline <= date {
                if store.update({ $0.restUntil = nil }), !defaults.bool(forKey: "haptics.disabled") {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private func footer(_ session: WorkoutSession) -> some View {
        VStack(spacing: 12) {
            if keyboardVisible {
                Button(action: dismissKeyboard) {
                    Label("Done editing", systemImage: "keyboard.chevron.compact.down").font(FitTheme.button(15))
                        .frame(maxWidth: .infinity, minHeight: 54).dashboardGlass(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                }.buttonStyle(RoutineEditorPressStyle())
            } else {
                if session.restUntil != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        WorkoutRestCard(session: session, now: context.date) { store.update { $0.restUntil = nil } }
                    }
                }
                HStack(spacing: 12) {
                    if !session.entries.isEmpty {
                        Button(action: chooseExercises) {
                            Image(systemName: "plus").font(.system(size: 20)).frame(width: 54, height: 54)
                                .dashboardGlass(in: RoundedRectangle(cornerRadius: 16), interactive: true)
                        }.buttonStyle(RoutineEditorPressStyle()).accessibilityLabel("Add exercise").accessibilityIdentifier("workoutAddExercise")
                    }
                    Button {
                        if session.entries.isEmpty { chooseExercises() } else { dismissKeyboard(); finishing = true }
                    } label: {
                        HStack {
                            Text(session.entries.isEmpty ? "Choose exercises" : "Finish workout")
                            Spacer(minLength: 4)
                            Image(systemName: session.entries.isEmpty ? "plus" : "checkmark")
                        }
                        .font(FitTheme.button(15)).padding(.horizontal, 18).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier(session.entries.isEmpty ? "workoutAddExercise" : "finishWorkout")
                }
            }
        }
        .frame(maxWidth: 560).padding(.horizontal, FitTheme.pageInset).padding(.vertical, 12)
        .frame(maxWidth: .infinity).background(.bar)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: session.restUntil != nil)
    }
    private func dismissKeyboard() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func chooseExercises() { dismissKeyboard(); replacing = nil; selecting = true }
    private func expandFirstEntry(_ session: WorkoutSession) {
        guard expandedEntry == nil else { return }
        expandedEntry = session.entries.first { !$0.skipped && $0.sets.contains { $0.completedAt == nil } }?.id ?? session.entries.first?.id
    }
    private func toggleSet(_ entryID: UUID, _ setID: UUID) {
        dismissKeyboard()
        let wasLogged = store.active?.entries.first { $0.id == entryID }?.sets.first { $0.id == setID }?.completedAt != nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { store.toggleSet(entryID: entryID, setID: setID) }
        if !wasLogged, store.active?.entries.first(where: { $0.id == entryID })?.sets.first(where: { $0.id == setID })?.completedAt != nil,
           !defaults.bool(forKey: "haptics.disabled") { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
    private func addSet(_ entryID: UUID) {
        dismissKeyboard()
        changeEntry(entryID) { entry in entry.sets.append(entry.sets.last?.nextWorkingSet() ?? WorkoutSet()) }
    }
    private func deleteSet(_ entryID: UUID, _ setID: UUID) {
        let latest = store.active?.completedSets.max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }?.id
        store.update { session in
            if let index = session.entries.firstIndex(where: { $0.id == entryID }) { session.entries[index].sets.removeAll { $0.id == setID } }
            if latest == setID { session.restUntil = nil }
        }
    }
    private func finish(_ status: SessionStatus) {
        dismissKeyboard()
        let id = store.active?.id
        if store.finish(status) { finished = store.history.first { $0.id == id } }
    }
    private func changeEntry(_ id: UUID, _ mutation: (inout WorkoutEntry) -> Void) {
        store.update { session in if let index = session.entries.firstIndex(where: { $0.id == id }) { mutation(&session.entries[index]) } }
    }
    private func setBinding(_ entry: UUID, _ set: UUID) -> Binding<WorkoutSet> {
        Binding(get: { store.active?.entries.first { $0.id == entry }?.sets.first { $0.id == set } ?? WorkoutSet() }, set: { value in
            changeEntry(entry) { item in if let index = item.sets.firstIndex(where: { $0.id == set }) { item.sets[index] = value } }
        })
    }
}

struct WorkoutSummary: View {
    let session: WorkoutSession
    let unit: WeightUnit
    var history: [WorkoutSession] = []
    private var records: [String] { Array(Set(WorkoutAnalytics.newRecords(in: session, history: history))).sorted() }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                WorkoutSessionHero(session: session, unit: unit, now: session.endedAt ?? .now)
                Label(session.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("New personal records", systemImage: "trophy").font(FitTheme.section(17)).foregroundStyle(FitTheme.dashboardAccent)
                        ForEach(records, id: \.self) { Text($0).font(FitTheme.body(14)) }
                    }.routinePanel()
                }
                if !session.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Session notes", systemImage: "note.text").font(FitTheme.section(15))
                        Text(session.notes).font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
                    }.routinePanel()
                }
                ForEach(session.entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ExerciseImageButton(exercise: entry.exercise, style: .thumbnail(60))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.exercise.name).font(FitTheme.section(16))
                                Text(entry.skipped ? "Skipped" : "\(entry.sets.filter { $0.completedAt != nil }.count) sets logged")
                                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }
                        }
                        let completed = entry.sets.filter { $0.completedAt != nil }
                        if !completed.isEmpty { Divider().overlay(.white.opacity(0.06)) }
                        ForEach(completed) { set in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(FitTheme.dashboardAccent).font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 4) {
                                    if set.type != .working { Text(set.type.rawValue).font(FitTheme.medium(10)).foregroundStyle(FitTheme.textSecondary) }
                                    Text(entry.exercise.kind == .duration ? "\(set.seconds.formatted()) sec" : "\(set.reps) reps").font(FitTheme.strong(15))
                                }
                                Spacer(minLength: 4)
                                if entry.exercise.kind == .weighted {
                                    Text("\(unit.display(set.loadKG).formatted()) \(unit.rawValue)").font(FitTheme.body(14)).monospacedDigit()
                                } else if entry.exercise.kind == .duration && set.distanceMeters > 0 {
                                    Text("\(set.distanceMeters.formatted()) m").font(FitTheme.body(14))
                                }
                            }
                        }
                        if completed.isEmpty && !entry.skipped { Text("No sets logged").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary) }
                        if !entry.notes.isEmpty { Text(entry.notes).font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary) }
                    }
                    .padding(FitTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
                    .dashboardGlass(in: RoundedRectangle(cornerRadius: 22))
                }
                if session.entries.contains(where: { $0.exercise.kind == .weighted }) {
                    Text("Volume includes logged working and drop sets. Warm-ups are kept in the session but excluded from volume.")
                        .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }
            }
            .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
        }
        .background(FitTheme.dashboardBackground).foregroundStyle(.white).tint(FitTheme.dashboardAccent)
        .navigationTitle("Workout summary").navigationBarTitleDisplayMode(.inline)
    }
}

struct WorkoutHistory: View {
    @Bindable var store: WorkoutStore
    let unit: WeightUnit
    @State private var deleting: UUID?
    var body: some View {
        List {
            if store.history.isEmpty { ContentUnavailableView("No workout history", systemImage: "calendar", description: Text("Finished, skipped and abandoned workouts will appear here.")) }
            if let error = store.error { Text(error).foregroundStyle(.red) }
            ForEach(store.history) { session in
                NavigationLink { WorkoutSummary(session: session, unit: unit, history: store.history) } label: {
                    VStack(alignment: .leading) { Text(session.title); Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.status.rawValue)").font(FitTheme.body(12)).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete", role: .destructive) { deleting = session.id } }
            }
        }.navigationTitle("Workout history")
            .confirmationDialog("Delete this workout and its sets?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Delete", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil } }
    }
}

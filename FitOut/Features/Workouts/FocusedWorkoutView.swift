import SwiftUI

struct ActiveWorkoutView: View {
    let store: WorkoutStore
    let gym: GymStore
    let defaults: UserDefaults
    let onMinimize: (() -> Void)?
    @State private var model: FocusedWorkoutModel
    @State private var choosingExercises = false
    @State private var configuringEntry: WorkoutEntry?
    @State private var editingPlan = false
    @State private var showTechnique = false
    @State private var showTiming = false
    @State private var showNote = false
    @State private var noteText = ""
    @State private var noteEntryID: UUID?
    @State private var noteSetID: UUID?
    @State private var finishing = false
    @State private var discarding = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(store: WorkoutStore, gym: GymStore, unit: WeightUnit, defaults: UserDefaults, onMinimize: (() -> Void)? = nil) {
        self.store = store; self.gym = gym; self.defaults = defaults
        self.onMinimize = onMinimize
        _model = State(initialValue: FocusedWorkoutModel(store: store, unit: unit))
    }
    var body: some View {
        Group {
            if let session = model.session {
                VStack(spacing: 0) {
                    header(session)
                    if model.phase == .workoutCompleted {
                        WorkoutSummary(session: session, unit: model.unit, history: store.history)
                    } else {
                        GeometryReader { viewport in
                            ScrollView {
                                VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                                    Button { editingPlan = true } label: {
                                        HStack {
                                            Label("Session exercises", systemImage: "list.bullet")
                                            Spacer()
                                            Text("\(session.entries.count)").monospacedDigit()
                                            Image(systemName: "arrow.up.arrow.down")
                                        }.font(FitTheme.button(14)).padding(.horizontal, 16).frame(minHeight: 48)
                                            .dashboardGlass(in: Capsule(), interactive: true)
                                    }.buttonStyle(.plain).disabled(!model.editingInputs.isEmpty).accessibilityIdentifier("manageSessionExercises")
                                    if let current = model.current {
                                        progress(session, entry: current.entry, set: current.set)
                                        exercise(current.entry)
                                        FocusedWorkoutStage(session: session, entry: current.entry, set: current.set, availableHeight: viewport.size.height, now: { model.now }) {
                                            keyboardDown(); model.togglePause()
                                        }
                                        FocusedWorkoutMetrics(session: session, unit: model.unit, now: { model.now })
                                        Button { configuringEntry = current.entry } label: {
                                            Label("Manage \(current.entry.sets.count) sets", systemImage: "slider.horizontal.3")
                                                .font(FitTheme.button(14)).frame(maxWidth: .infinity, minHeight: 48)
                                        }.buttonStyle(.plain).dashboardGlass(in: Capsule(), interactive: true)
                                            .accessibilityIdentifier("manageWorkoutSets")
                                        if [.ready, .activeSet, .exerciseTransition, .paused].contains(model.phase), current.set.status == .pending {
                                            inputs(current.entry, set: current.set)
                                            HStack {
                                                Button("Skip set", systemImage: "forward.end") { act(.skipSet, expected: current.set.id) }
                                                    .disabled(model.phase == .paused || !model.editingInputs.isEmpty).accessibilityIdentifier("skipWorkoutSet")
                                                Spacer()
                                                Button("Add note", systemImage: "note.text.badge.plus") { openNote(current.entry.id, current.set.id) }
                                            }.font(FitTheme.medium(13)).frame(minHeight: 44)
                                        }
                                    } else {
                                        WorkoutEmptyState()
                                        Text(session.entries.isEmpty ? "Choose exercises to begin. Each set saves as soon as you complete or skip it." : "Your sets are recorded. Finish when you're ready.")
                                            .font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
                                    }
                                    if let undo = session.execution?.undo {
                                        Button("Undo last \(undo.before.status == .pending ? "set action" : "action")", systemImage: "arrow.uturn.backward") { act(.undo) }
                                            .font(FitTheme.medium(13)).frame(minHeight: 44).accessibilityIdentifier("undoWorkoutSet")
                                        Text("Undo restores the inputs and resets that set's timer.").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                                    }
                                }.frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
                            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
                        }
                    }
                }.safeAreaInset(edge: .bottom, spacing: 0) { footer(session) }
            } else {
                ContentUnavailableView("No active workout", systemImage: "dumbbell", description: Text("Close this screen to start or resume a workout."))
                    .safeAreaInset(edge: .bottom) { Button("Close", action: minimize).frame(minHeight: 54) }
            }
        }
        .foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent).background(FitTheme.dashboardBackground)
        .toolbar(.hidden, for: .navigationBar).presentationDragIndicator(.visible).presentationCornerRadius(30)
        .accessibilityIdentifier(model.phase == .workoutCompleted ? "focusedWorkoutSummary" : "activeWorkoutScreen")
        .onAppear { store.editorAppeared(); model.activate() }
        .onDisappear { store.editorDisappeared(); model.deactivate() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.activate() } else { model.deactivate() } }
        .onChange(of: model.session?.execution) { _, _ in model.refresh() }
        .onChange(of: model.session?.restUntil) { _, _ in model.refresh() }
        .onChange(of: model.session?.status) { _, _ in model.refresh() }
        .sheet(isPresented: $choosingExercises) {
            NavigationStack {
                QuickWorkoutSetupView(store: store, gym: gym, unit: model.unit, defaults: nil, addingToSession: true) { model.refresh(); choosingExercises = false }
            }
        }
        .sheet(item: $configuringEntry) { entry in
            NavigationStack {
                WorkoutEntryConfigurationView(entry: entry, unit: model.unit, reference: { edited, set in
                    WorkoutRecall.reference(for: edited, setID: set.id, current: store.active, history: store.history)
                }, protectedSetID: model.session?.execution?.setID) { edited in
                    if store.configureExercise(edited, original: entry) { model.refresh(); configuringEntry = nil }
                }
                .safeAreaInset(edge: .bottom) {
                    if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red).padding() }
                }
            }
        }
        .sheet(isPresented: $editingPlan, onDismiss: { model.refresh() }) {
            NavigationStack { WorkoutSessionConfigurationView(store: store, gym: gym, unit: model.unit) }
        }
        .sheet(isPresented: $showTiming) { if let session = model.session { WorkoutTimingDetails(session: session, unit: model.unit) } }
        .sheet(isPresented: $showTechnique) { if let exercise = model.current?.entry.exercise { technique(exercise) } }
        .sheet(isPresented: $showNote) { noteSheet }
        .confirmationDialog("Finish this workout?", isPresented: $finishing, titleVisibility: .visible) {
            Button("Finish workout") { act(.finish) }
        } message: { Text("Recorded sets are saved. Unfinished sets stay unlogged.") }
        .confirmationDialog("Discard this workout?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { if let id = model.sessionID, store.delete(id) { minimize() } }
        } message: { Text("This deletes this session, its sets and notes. Your saved routine stays available.") }
        .alert("Workout could not be updated", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private func header(_ session: WorkoutSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: minimize) {
                Image(systemName: "chevron.down").frame(width: 44, height: 44).dashboardGlass(in: Circle(), interactive: true)
            }.buttonStyle(.plain).accessibilityLabel("Minimize workout").accessibilityIdentifier("minimizeWorkout")
            VStack(alignment: .leading, spacing: 4) {
                Text(session.routineID == nil ? "QUICK WORKOUT" : "PLANNED ROUTINE").font(FitTheme.medium(9)).tracking(1.1).foregroundStyle(FitTheme.dashboardAccent)
                Text(session.title).font(FitTheme.section(14)).lineLimit(2)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text("Workout time · " + WorkoutDisplay.clock(session.duration(at: model.now))).font(FitTheme.medium(11)).monospacedDigit().foregroundStyle(FitTheme.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if session.isActive {
                    Button(session.status == .paused ? "Resume workout" : "Pause workout", systemImage: session.status == .paused ? "play" : "pause") { model.togglePause() }
                    Button("Manage session exercises", systemImage: "list.bullet.rectangle") { editingPlan = true }
                    Button("Add exercises", systemImage: "plus") { choosingExercises = true }
                    if let entry = model.current?.entry {
                        Button("Edit sets, weight & reps", systemImage: "slider.horizontal.3") { configuringEntry = entry }
                        Button("Add set to this exercise", systemImage: "plus.rectangle.on.rectangle") { store.appendSet(entryID: entry.id); model.refresh() }
                    }
                    if let set = model.current?.set, set.status == .pending {
                        Picker("Set type", selection: Binding(get: { model.current?.set.type ?? .working }, set: {
                            var value = model.current?.set ?? set; value.type = $0; model.editSet(value)
                        })) { ForEach(SetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    }
                    if let presentation = WorkoutRuntime.presentation { Button("Show Live Activity") { presentation.showLiveActivity() } }
                    Button("Finish workout", systemImage: "checkmark") { finishing = true }
                    Button("Discard workout", role: .destructive) { discarding = true }
                }
                Button("Timing & timeline", systemImage: "clock") { showTiming = true }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).dashboardGlass(in: Circle(), interactive: true) }
                .accessibilityLabel("Workout options")
        }.padding(.horizontal, FitTheme.pageInset).padding(.vertical, 10)
    }
    private func progress(_ session: WorkoutSession, entry: WorkoutEntry, set: WorkoutSet) -> some View {
        VStack(spacing: 9) {
            HStack {
                Text("Exercise \((session.entries.firstIndex { $0.id == entry.id } ?? 0) + 1) / \(session.entries.count)")
                Spacer()
                Text("Set \((entry.sets.firstIndex { $0.id == set.id } ?? 0) + 1) / \(entry.sets.count)")
            }.font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
            ProgressView(value: session.setProgress).tint(FitTheme.dashboardAccent)
                .accessibilityLabel("Workout progress").accessibilityValue("\(session.completedSets.count) completed, \(session.skippedSets.count) skipped, \(session.remainingSetCount) remaining")
        }
    }
    private func exercise(_ entry: WorkoutEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.phase == .exerciseTransition { Text("NEXT EXERCISE").font(FitTheme.medium(10)).tracking(1).foregroundStyle(FitTheme.dashboardAccent) }
            Text(entry.exercise.name).font(FitTheme.display(23)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: 12) {
                Text((entry.exercise.equipment == "None" ? "No equipment" : entry.exercise.equipment) + " · " + entry.exercise.muscles.map(\.title).joined(separator: ", "))
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { showTechnique = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 19)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Exercise details and technique")
            }
        }
    }
    private func inputs(_ entry: WorkoutEntry, set: WorkoutSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(set.type.rawValue).font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
            if entry.exercise.kind == .weighted {
                Picker("Weight unit", selection: Binding(get: { model.unit }, set: { model.selectUnit($0) })) {
                    Text("kg").tag(WeightUnit.kg); Text("lb").tag(WeightUnit.lbs)
                }.pickerStyle(.segmented).frame(maxWidth: 180).disabled(!model.editingInputs.isEmpty).accessibilityIdentifier("workoutWeightUnit")
            }
            if let previous = store.reference(entryID: entry.id, setID: set.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(previous.isCurrentWorkout ? "Previous set" : "Last time · " + previous.date.formatted(date: .abbreviated, time: .omitted)).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                    Text(entry.exercise.kind == .duration ? "\(previous.set.seconds.formatted()) sec" : "\(previous.set.reps) reps" + (entry.exercise.kind == .weighted ? " · \(model.unit.display(previous.set.loadKG).formatted()) \(model.unit.rawValue)" : ""))
                        .font(FitTheme.medium(13))
                    if set.startedAt == nil { Button("Use previous") { store.reusePrevious(entryID: entry.id, setID: set.id) }.font(FitTheme.medium(12)).frame(minHeight: 44) }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { fields(entry.exercise.kind, set: set) }
                VStack(spacing: 12) { fields(entry.exercise.kind, set: set) }
            }
            if let target = set.plannedTarget {
                Text(entry.exercise.kind == .duration ? "Planned · \(target.seconds.formatted()) sec" : "Planned · \(target.repMin)–\(target.repMax) reps" + (target.loadKG.map { " · \(model.unit.display($0).formatted()) \(model.unit.rawValue)" } ?? ""))
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            if let error = model.inputError { Text(error).font(FitTheme.body(12)).foregroundStyle(.red) }
            DisclosureGroup("Effort & rest") {
                Toggle("Record RPE", isOn: Binding(get: { model.current?.set.rpe != nil }, set: {
                    var value = model.current?.set ?? set; value.rpe = $0 ? 7 : nil; model.editSet(value)
                }))
                if set.rpe != nil {
                    Stepper("RPE · \((model.current?.set.rpe ?? 7).formatted()) / 10", value: Binding(get: { model.current?.set.rpe ?? 7 }, set: {
                        var value = model.current?.set ?? set; value.rpe = $0; model.editSet(value)
                    }), in: 1...10, step: 0.5)
                }
                Stepper("Rest after set · \(model.current?.set.restSeconds ?? entry.restSeconds)s", value: Binding(get: { model.current?.set.restSeconds ?? entry.restSeconds }, set: {
                    var value = model.current?.set ?? set; value.restSeconds = $0; model.editSet(value)
                }), in: 0...3600, step: 15)
            }.font(FitTheme.body(13))
            Button(entry.exercise.kind == .weighted ? "Apply weight to remaining sets" : "Apply inputs to remaining sets", systemImage: "arrow.down.to.line") {
                keyboardDown(); store.repeatInputs(entryID: entry.id, setID: set.id)
            }.font(FitTheme.medium(12)).frame(minHeight: 44)
        }
    }
    @ViewBuilder private func fields(_ kind: ExerciseKind, set: WorkoutSet) -> some View {
        if kind == .weighted {
            WorkoutNumberWheel(title: "Weight · \(model.unit.rawValue)", value: Binding(get: { model.unit.display(model.current?.set.id == set.id ? model.current?.set.loadKG ?? set.loadKG : set.loadKG) }, set: {
                guard var value = model.current?.set, value.id == set.id else { return }
                value.loadKG = model.unit.kilograms($0); model.editSet(value, field: .load)
            }), step: model.unit == .kg ? 0.5 : 1, maximum: model.unit.display(1000), editingChanged: { active in
                if active { model.editingInputs.insert(.load) } else { model.editingInputs.remove(.load) }
            }).id("\(set.id)-load-\(model.unit.rawValue)")
        }
        if kind != .duration {
            WorkoutNumberWheel(title: "Actual reps", value: Binding(get: { Double(model.current?.set.id == set.id ? model.current?.set.reps ?? set.reps : set.reps) }, set: {
                guard var value = model.current?.set, value.id == set.id else { return }
                guard $0.isFinite, (0...1000).contains($0) else { model.rejectInput(.reps, message: "Enter reps between 0 and 1,000."); return }
                value.reps = Int($0); model.editSet(value, field: .reps)
            }), integer: true, editingChanged: { active in
                if active { model.editingInputs.insert(.reps) } else { model.editingInputs.remove(.reps) }
            }).id("\(set.id)-reps")
        } else {
            WorkoutLogNumberField(title: "Target seconds", value: Binding(get: { model.current?.set.seconds ?? 0 }, set: { var value = model.current?.set ?? set; value.seconds = $0; model.editSet(value, field: .seconds) }), step: 5, maximum: 86400)
            WorkoutLogNumberField(title: "Meters (optional)", value: Binding(get: { model.current?.set.distanceMeters ?? 0 }, set: { var value = model.current?.set ?? set; value.distanceMeters = $0; model.editSet(value, field: .distance) }), step: 50, maximum: 1_000_000)
        }
    }
    private func footer(_ session: WorkoutSession) -> some View {
        let expectedPhase = model.phase
        let expectedSet = model.current?.set.id
        return VStack(spacing: 8) {
            if model.phase == .resting { Button("+15 seconds rest", systemImage: "plus") { act(.extendRest) }.font(FitTheme.medium(13)).frame(minHeight: 44) }
            if model.phase == .workoutCompleted, session.execution?.undo != nil { Button("Undo last set", systemImage: "arrow.uturn.backward") { act(.undo) }.frame(minHeight: 44) }
            Button { if model.phase == expectedPhase && model.current?.set.id == expectedSet { primaryAction() } } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(primaryTitle).font(FitTheme.button(17))
                        if let detail = WorkoutActionPreview(session: session).detail {
                            Text(detail).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: model.phase == .activeSet ? "checkmark" : model.phase == .paused ? "play.fill" : "arrow.right")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 54, height: 54).background(FitTheme.dashboardAccent, in: Circle())
                        .accessibilityHidden(true)
                }.padding(16).frame(maxWidth: .infinity, minHeight: 86)
                    .foregroundStyle(FitTheme.textPrimary).background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 26))
                    .contentShape(RoundedRectangle(cornerRadius: 26))
            }.buttonStyle(RoutineEditorPressStyle()).disabled(!model.editingInputs.isEmpty || model.phase == .activeSet && model.inputError != nil).accessibilityIdentifier(model.phase == .activeSet ? "completeSet" : "focusedWorkoutPrimary")
        }.frame(maxWidth: 560).padding(.horizontal, FitTheme.pageInset).padding(.vertical, 10).frame(maxWidth: .infinity).background(.bar)
    }
    private var primaryTitle: String {
        if model.phase == .workoutCompleted { return "Close summary" }
        if model.phase == .paused { return "Resume workout" }
        if model.current == nil { return model.session?.entries.isEmpty == true ? "Choose exercises" : "Finish workout" }
        switch model.phase { case .activeSet: return "Complete Set"; case .resting: return "Skip Rest"; case .paused: return "Resume workout"; case .exerciseTransition: return "Start next exercise"; default: return "Start set" }
    }
    private func primaryAction() {
        keyboardDown()
        if model.phase == .workoutCompleted { minimize(); return }
        if model.phase == .paused { model.togglePause(); return }
        if model.current == nil { if model.session?.entries.isEmpty == true { choosingExercises = true } else { finishing = true }; return }
        switch model.phase {
        case .paused: model.togglePause()
        case .resting: act(.skipRest)
        case .activeSet: act(.completeSet, expected: model.current?.set.id)
        default: act(.startSet, expected: model.current?.set.id)
        }
    }
    private func act(_ command: WorkoutCommand, expected: UUID? = nil) {
        keyboardDown()
        model.perform(command, expectedSet: expected)
    }
    private func keyboardDown() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    private func minimize() { keyboardDown(); if let onMinimize { onMinimize() } else { dismiss() } }
    private func openNote(_ entryID: UUID, _ setID: UUID) {
        noteEntryID = entryID; noteSetID = setID; noteText = model.current?.set.note ?? ""; showNote = true
    }
    private var noteSheet: some View {
        NavigationStack {
            Form { TextField("Set note", text: $noteText, axis: .vertical).lineLimit(4...12) }
                .navigationTitle("Set note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showNote = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        if store.update({ session in
                            if let e = session.entries.firstIndex(where: { $0.id == noteEntryID }), let s = session.entries[e].sets.firstIndex(where: { $0.id == noteSetID }) { session.entries[e].sets[s].note = noteText }
                        }) { showNote = false }
                    } }
                }
        }.presentationDetents([.medium, .large])
    }
    private func technique(_ exercise: ExerciseDefinition) -> some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                ExerciseImageButton(exercise: exercise, style: .detail)
                Text(exercise.name).font(FitTheme.section(20))
                Label(exercise.equipment == "None" ? "No equipment" : exercise.equipment, systemImage: "dumbbell").font(FitTheme.body(14))
                Text("Primary · " + exercise.muscles.map(\.title).joined(separator: ", ")).font(FitTheme.body(14))
                if !exercise.secondary.isEmpty { Text("Secondary · " + exercise.secondary.map(\.title).joined(separator: ", ")).font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary) }
                if !exercise.instructions.isEmpty { Text(exercise.instructions).font(FitTheme.body(15)) }
            }.padding(FitTheme.pageInset) }.background(FitTheme.dashboardBackground)
                .navigationTitle("Technique").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { showTechnique = false } }
        }
    }
}

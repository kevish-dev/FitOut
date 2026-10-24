import SwiftUI

/// One sheet stays open as setup becomes a running session; browsing never starts a timer.
struct QuickWorkoutFlow: View {
    let store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @State private var showingSession: Bool
    init(store: WorkoutStore, gym: GymStore, unit: WeightUnit, defaults: UserDefaults) {
        self.store = store; self.gym = gym; self.unit = unit; self.defaults = defaults
        _showingSession = State(initialValue: store.active != nil)
    }
    var body: some View {
        if showingSession {
            ActiveWorkoutView(store: store, gym: gym, unit: unit, defaults: defaults)
        } else {
            QuickWorkoutSetupView(store: store, gym: gym, unit: unit, defaults: defaults, onStarted: { showingSession = true })
        }
    }
}

struct QuickWorkoutSetupView: View {
    let store: WorkoutStore
    let gym: GymStore
    @State private var unit: WeightUnit
    @State private var saved: QuickWorkoutDraftStore
    var addingToSession = false
    var onAdded: (() -> Void)?
    var onStarted: (() -> Void)?
    @State private var selecting = false
    @State private var editing: WorkoutEntry?
    @State private var discarding = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(store: WorkoutStore, gym: GymStore, unit: WeightUnit, defaults: UserDefaults?, addingToSession: Bool = false, onAdded: (() -> Void)? = nil, onStarted: (() -> Void)? = nil) {
        self.store = store; self.gym = gym; self.addingToSession = addingToSession; self.onAdded = onAdded; self.onStarted = onStarted
        _unit = State(initialValue: unit)
        _saved = State(initialValue: QuickWorkoutDraftStore(defaults: addingToSession ? nil : defaults))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(addingToSession ? "Add to your session" : "Build your workout").font(FitTheme.display(25))
                    Text(addingToSession ? "Choose movements and configure their sets before adding them." : "Choose your exercises, set your targets, then start. Your timer stays off until you're ready.")
                        .font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
                }
                if !addingToSession {
                    TextField("Workout name", text: $saved.draft.title).font(FitTheme.section(17))
                        .padding(14).fitSurface(radius: 14).accessibilityIdentifier("quickWorkoutName")
                }
                HStack {
                    Text("\(saved.draft.entries.count) exercises · \(saved.draft.entries.flatMap(\.sets).count) sets")
                        .font(FitTheme.medium(13)).foregroundStyle(FitTheme.textSecondary)
                    Spacer()
                    Picker("Weight unit", selection: $unit) {
                        Text("kg").tag(WeightUnit.kg); Text("lb").tag(WeightUnit.lbs)
                    }.pickerStyle(.segmented).frame(maxWidth: 125)
                }
                if saved.draft.entries.isEmpty {
                    VStack(spacing: 16) {
                        Image("RoutineEquipment").resizable().scaledToFit().frame(height: 130).accessibilityHidden(true)
                        Text("What are you training?").font(FitTheme.section(20))
                        Text("Select several exercises together. Each one gets its own editable sets.")
                            .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                ForEach(Array(saved.draft.entries.enumerated()), id: \.element.id) { index, entry in
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            ExerciseImageButton(exercise: entry.exercise, style: .thumbnail(64))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.exercise.name).font(FitTheme.section(16))
                                Text("\(entry.sets.count) sets · \(entry.restSeconds)s rest").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                                if let set = entry.sets.first {
                                    Text(WorkoutConfigurationDisplay.inputs(set, kind: entry.exercise.kind, unit: unit))
                                        .font(FitTheme.medium(12)).foregroundStyle(FitTheme.dashboardAccent)
                                    if let previous = WorkoutRecall.reference(for: entry, setID: set.id, current: addingToSession ? store.active : nil, history: store.history) {
                                        Text("Last recorded · " + WorkoutConfigurationDisplay.inputs(previous.set, kind: entry.exercise.kind, unit: unit))
                                            .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Menu {
                                if index > 0 { Button("Move up", systemImage: "arrow.up") { saved.draft.entries.swapAt(index, index - 1) } }
                                if index + 1 < saved.draft.entries.count { Button("Move down", systemImage: "arrow.down") { saved.draft.entries.swapAt(index, index + 1) } }
                                Button("Remove exercise", role: .destructive) { saved.draft.entries.removeAll { $0.id == entry.id } }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel("Options for \(entry.exercise.name)")
                        }
                        Button { editing = entry } label: {
                            Label("Edit sets, weight & reps", systemImage: "slider.horizontal.3")
                                .font(FitTheme.button(13)).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.plain).dashboardGlass(in: Capsule(), interactive: true)
                            .accessibilityIdentifier("configureQuickExercise-\(entry.exercise.id)")
                    }.padding(FitTheme.cardInset).background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        .transition(.opacity)
                }
                .animation(FitMotion.change(reduceMotion: reduceMotion), value: saved.draft.entries.map(\.id))
                Button { selecting = true } label: {
                    Label(saved.draft.entries.isEmpty ? "Choose exercises" : "Add exercises", systemImage: "plus")
                        .font(FitTheme.button(16)).frame(maxWidth: .infinity, minHeight: 54)
                }.buttonStyle(.plain).dashboardGlass(in: Capsule(), interactive: true).accessibilityIdentifier("configureQuickExercises")
                if let error = saved.error ?? store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red) }
                if !addingToSession { Text("Setup is saved on this iPhone. Previous recorded weights and reps are filled in when available.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary) }
            }.frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively).background(FitTheme.dashboardBackground)
        .foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent)
        .navigationTitle(addingToSession ? "Configure exercises" : "Quick workout").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(addingToSession ? "Cancel" : "Close") { dismiss() } }
            if !addingToSession, !saved.draft.entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { Button("Reset", systemImage: "arrow.counterclockwise") { discarding = true } }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { keyboardDown() } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                keyboardDown()
                if addingToSession {
                    if store.addConfiguredExercises(saved.draft.entries) { onAdded?(); dismiss() }
                } else if store.startQuickWorkout(saved.draft, unit: unit) { saved.clear(); onStarted?() }
            } label: {
                Label(addingToSession ? "Add configured exercises" : "Start workout", systemImage: addingToSession ? "plus" : "play.fill")
                    .font(FitTheme.button(16)).frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(.white).background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(RoutineEditorPressStyle()).disabled(!saved.draft.isValid)
                .accessibilityIdentifier("startConfiguredWorkout")
                .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity).background(.bar)
                .workoutControlClearance("workout.configuration.actions")
        }
        .sheet(isPresented: $selecting) {
            NavigationStack {
                ExerciseBrowser(store: gym, title: "Choose exercises", mode: .multiple,
                    selectionHint: addingToSession ? "Select movements, then configure their sets before adding them to your session." : "Select all your movements, then configure their sets. Your workout won't start yet.", previousPerformance: { exercise in
                        let sample = WorkoutEntry(exercise: exercise, sets: [WorkoutSet()])
                        return WorkoutRecall.reference(for: sample, setID: sample.sets[0].id, current: addingToSession ? store.active : nil, history: store.history)
                            .map { WorkoutConfigurationDisplay.inputs($0.set, kind: exercise.kind, unit: unit) }
                    }) { exercises in
                    saved.draft.add(exercises, current: addingToSession ? store.active : nil, history: store.history)
                    selecting = false
                }
            }
        }
        .sheet(item: $editing) { entry in
            NavigationStack {
                WorkoutEntryConfigurationView(entry: entry, unit: unit, reference: { edited, set in
                    WorkoutRecall.reference(for: edited, setID: set.id, current: addingToSession ? store.active : nil, history: store.history)
                }) { edited in
                    if let index = saved.draft.entries.firstIndex(where: { $0.id == edited.id }) { saved.draft.entries[index] = edited }
                    editing = nil
                }
            }
        }
        .confirmationDialog("Clear this workout setup?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Clear setup", role: .destructive) { saved.clear() }
        } message: { Text("Recorded workouts and previous performance stay saved.") }
        .accessibilityIdentifier("quickWorkoutSetup")
    }
    private func keyboardDown() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}

enum WorkoutConfigurationDisplay {
    static func inputs(_ set: WorkoutSet, kind: ExerciseKind, unit: WeightUnit) -> String {
        switch kind {
        case .duration: return "\(set.seconds.formatted()) sec" + (set.distanceMeters > 0 ? " · \(set.distanceMeters.formatted()) m" : "")
        case .bodyweight: return "\(set.reps) reps"
        case .weighted: return "\(unit.display(set.loadKG).formatted()) \(unit.rawValue) × \(set.reps) reps"
        }
    }
}

/// Local edit buffer: Done applies valid inputs; Cancel leaves the exercise untouched.
struct WorkoutEntryConfigurationView: View {
    @State var entry: WorkoutEntry
    let unit: WeightUnit
    let reference: (WorkoutEntry, WorkoutSet) -> WorkoutSetReference?
    var protectedSetID: UUID? = nil
    let save: (WorkoutEntry) -> Void
    @State private var invalid: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var valid: Bool {
        invalid.isEmpty && !entry.sets.isEmpty && entry.sets.allSatisfy { set in
            set.isValid && (set.status != .pending || (entry.exercise.kind == .duration ? set.seconds > 0 : set.reps > 0))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    ExerciseArtwork(exercise: entry.exercise, size: 76)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(entry.exercise.name).font(FitTheme.section(21))
                        Text(entry.exercise.trackingTitle).font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                    }
                }
                HStack(spacing: 12) {
                    Text("Sets").font(FitTheme.section(16))
                    Spacer()
                    Button {
                        if canRemoveLast, let removed = entry.sets.popLast() { invalid = invalid.filter { !$0.hasPrefix(removed.id.uuidString) } }
                    } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                    }.disabled(!canRemoveLast).accessibilityLabel("Remove last unstarted set")
                    Text("\(entry.sets.count)").font(FitTheme.strong(20)).monospacedDigit().frame(minWidth: 26)
                        .contentTransition(.numericText()).animation(FitMotion.change(reduceMotion: reduceMotion), value: entry.sets.count)
                    Button(action: addSet) { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .disabled(entry.sets.count >= 100).accessibilityLabel("Add set").accessibilityIdentifier("addConfiguredSet")
                }.buttonStyle(.plain)
                Stepper("Rest · \(entry.restSeconds) sec", value: $entry.restSeconds, in: 0...3600, step: 15).font(FitTheme.medium(14))
                    .onChange(of: entry.restSeconds) { _, seconds in
                        for index in entry.sets.indices where entry.sets[index].status == .pending { entry.sets[index].restSeconds = seconds }
                    }
                ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Set \(index + 1)").font(FitTheme.section(16))
                            if set.status != .pending { Label(set.status == .completed ? "Logged" : "Skipped", systemImage: set.status == .completed ? "checkmark.circle" : "forward.end").font(FitTheme.body(12)) }
                            Spacer()
                            if set.status == .pending {
                                Menu {
                                    if set.startedAt == nil {
                                        Picker("Set type", selection: setBinding(set).type) { ForEach(SetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                                    }
                                    Button("Apply to remaining sets", systemImage: "arrow.down.to.line") {
                                        for i in entry.sets.indices where i > index && entry.sets[i].status == .pending && entry.sets[i].startedAt == nil {
                                            entry.sets[i] = WorkoutRecall.copyInputs(entry.sets[i], from: entry.sets[index], kind: entry.exercise.kind)
                                        }
                                    }
                                    if set.startedAt == nil, set.id != protectedSetID, entry.sets.count > 1 {
                                        Button("Remove set", role: .destructive) {
                                            entry.sets.removeAll { $0.id == set.id }; invalid = invalid.filter { !$0.hasPrefix(set.id.uuidString) }
                                        }
                                    }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Set \(index + 1) options")
                            }
                        }
                        if let previous = reference(entry, set) {
                            Text((previous.isCurrentWorkout ? "Previous set · " : "Last time · ") + WorkoutConfigurationDisplay.inputs(previous.set, kind: entry.exercise.kind, unit: unit))
                                .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                        }
                        if set.status == .pending {
                            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                            layout { fields(set) }
                            Text(set.type.rawValue).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                        } else {
                            Text(WorkoutConfigurationDisplay.inputs(set, kind: entry.exercise.kind, unit: unit)).font(FitTheme.medium(15))
                        }
                    }.padding(.vertical, 4).transition(.opacity)
                    Divider()
                }
                .animation(FitMotion.change(reduceMotion: reduceMotion), value: entry.sets.map(\.id))
            }.frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
        }
        .background(FitTheme.dashboardBackground).foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent)
        .navigationTitle("Sets & targets").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { if valid { save(entry) } }.disabled(!valid).accessibilityIdentifier("saveExerciseConfiguration") }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done typing") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
        }
        .interactiveDismissDisabled(!invalid.isEmpty)
    }
    private var canRemoveLast: Bool {
        guard entry.sets.count > 1, let last = entry.sets.last else { return false }
        return last.status == .pending && last.startedAt == nil && last.id != protectedSetID
    }
    private func addSet() {
        guard entry.sets.count < 100 else { return }
        var next = entry.sets.last(where: { $0.type == .working })?.nextWorkingSet() ?? WorkoutSet(seconds: entry.exercise.kind == .duration ? 30 : 0)
        next.restSeconds = entry.restSeconds
        next.editedInputs = [.load, .reps, .seconds, .distance]
        entry.sets.append(next)
    }
    private func setBinding(_ fallback: WorkoutSet) -> Binding<WorkoutSet> {
        Binding(get: { entry.sets.first { $0.id == fallback.id } ?? fallback }, set: { value in
            if let index = entry.sets.firstIndex(where: { $0.id == value.id }) { entry.sets[index] = value }
        })
    }
    @ViewBuilder private func fields(_ set: WorkoutSet) -> some View {
        if entry.exercise.kind == .weighted { number(set, field: .load, title: "Weight · \(unit.rawValue)", value: unit.display(set.loadKG), maximum: unit.display(1000), step: unit == .kg ? 2.5 : 5) }
        if entry.exercise.kind == .duration {
            number(set, field: .seconds, title: "Seconds", value: set.seconds, maximum: 86400, step: 5)
            number(set, field: .distance, title: "Meters (optional)", value: set.distanceMeters, maximum: 1_000_000, step: 50)
        } else { number(set, field: .reps, title: "Reps", value: Double(set.reps), maximum: 1000, step: 1) }
    }
    private func number(_ set: WorkoutSet, field: WorkoutInputField, title: String, value: Double, maximum: Double, step: Double) -> some View {
        let id = set.id.uuidString + field.rawValue
        let number = (entry.sets.firstIndex { $0.id == set.id } ?? 0) + 1
        return WorkoutConfigurationNumber(title: title, accessibilityTitle: "Set \(number) \(title)", value: value, maximum: maximum, step: step, integer: field == .reps,
            positive: field == .reps || field == .seconds) { number, isValid in
            if !isValid { invalid.insert(id); return }
            invalid.remove(id)
            guard let index = entry.sets.firstIndex(where: { $0.id == set.id }) else { return }
            switch field {
            case .load: entry.sets[index].loadKG = unit.kilograms(number)
            case .reps: entry.sets[index].reps = Int(number)
            case .seconds: entry.sets[index].seconds = number
            case .distance: entry.sets[index].distanceMeters = number
            }
            entry.sets[index].editedInputs = (entry.sets[index].editedInputs ?? []).union([field])
        }.id(id)
    }
}

private struct WorkoutConfigurationNumber: View {
    let title: String
    let accessibilityTitle: String
    let value: Double
    let maximum: Double
    let step: Double
    let integer: Bool
    let positive: Bool
    let changed: (Double, Bool) -> Void
    @State private var text = ""
    @State private var valid = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
            TextField("0", text: $text).keyboardType(integer ? .numberPad : .decimalPad)
                .font(FitTheme.strong(23)).monospacedDigit().multilineTextAlignment(.center).frame(minHeight: 52)
                .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(accessibilityTitle)
                .onChange(of: text) { _, input in
                    let number = WorkoutConfigurationValue.parse(input, maximum: maximum, integer: integer, positive: positive)
                    valid = number != nil
                    changed(number ?? 0, valid)
                }
            HStack {
                Button { adjust(-step) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }.accessibilityLabel("Decrease \(title)")
                Spacer()
                Button { adjust(step) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Increase \(title)")
            }.buttonStyle(.plain)
            if !valid { Text("Enter \(positive ? "a positive" : "a valid") number up to \(maximum.formatted()).").font(FitTheme.body(11)).foregroundStyle(.red) }
        }.frame(minWidth: 108, maxWidth: .infinity)
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, new in if valid { text = formatted(new) } }
    }
    private func formatted(_ number: Double) -> String { number.formatted(.number.grouping(.never).precision(.fractionLength(0...2))) }
    private func adjust(_ delta: Double) { text = formatted(min(maximum, max(positive ? 1 : 0, ((value + delta) * 100).rounded() / 100))) }
}

struct WorkoutSessionConfigurationView: View {
    let store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    @State private var editing: WorkoutEntry?
    @State private var adding = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your workout plan").font(FitTheme.display(23))
                Text("Edit any exercise's remaining sets. Recorded sets and running timers stay intact.")
                    .font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
                ForEach(store.active?.entries ?? []) { entry in
                    Button { editing = entry } label: {
                        HStack(spacing: 14) {
                            ExerciseArtwork(exercise: entry.exercise, size: 60)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.exercise.name).font(FitTheme.section(16))
                                Text("\(entry.sets.filter { $0.status == .pending }.count) remaining · \(entry.sets.count) sets")
                                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                        }.padding(FitTheme.cardInset).background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                }
                Button { adding = true } label: {
                    Label("Add exercises", systemImage: "plus").font(FitTheme.button(15)).frame(maxWidth: .infinity, minHeight: 50)
                }.buttonStyle(.plain).dashboardGlass(in: Capsule(), interactive: true)
            }.frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
        }.background(FitTheme.dashboardBackground).foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent)
            .navigationTitle("Workout plan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { original in
                NavigationStack {
                    WorkoutEntryConfigurationView(entry: original, unit: unit, reference: { entry, set in
                        WorkoutRecall.reference(for: entry, setID: set.id, current: store.active, history: store.history)
                    }, protectedSetID: store.active?.execution?.setID) { edited in
                        if store.configureExercise(edited, original: original) { editing = nil }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red).padding() }
                    }
                }
            }
            .sheet(isPresented: $adding) {
                NavigationStack { QuickWorkoutSetupView(store: store, gym: gym, unit: unit, defaults: nil, addingToSession: true, onAdded: { adding = false }) }
            }
    }
}

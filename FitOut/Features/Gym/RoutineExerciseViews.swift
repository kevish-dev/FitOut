import SwiftUI

struct RoutineExerciseCard: View {
    @Binding var plan: PlannedExercise
    let definition: ExerciseDefinition?
    let unit: WeightUnit
    let canMoveUp: Bool
    let canMoveDown: Bool
    let replace: () -> Void
    let remove: () -> Void
    let move: (Int) -> Void
    @State private var expanded = false
    @State private var removing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var targets: Binding<[PlannedSet]> {
        Binding(get: { plan.setTargets ?? [] }, set: { plan.setTargets = $0 })
    }
    private var targetSummary: String {
        let values = plan.resolvedSets
        if definition?.kind == .duration {
            let times = Set(values.map(\.seconds))
            if times.count == 1, let seconds = values.first?.seconds {
                return seconds > 0 ? "\(seconds.formatted()) sec / set" : "Set a duration"
            }
            return "Timed targets"
        }
        let ranges = Set(values.map { "\($0.repMin)–\($0.repMax)" })
        guard ranges.count == 1, let first = values.first else { return "Mixed rep targets" }
        return first.repMin == first.repMax ? "\(first.repMin) reps" : "\(first.repMin)–\(first.repMax) reps"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if plan.setTargets == nil {
                        var values = plan.resolvedSets
                        if definition?.kind == .duration { for index in values.indices { values[index].seconds = 30 } }
                        plan.setTargets = values
                    }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        ExerciseArtwork(exercise: definition, size: typeSize.isAccessibilitySize ? 44 : 80)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(definition?.name ?? "Unavailable exercise").font(FitTheme.section(16))
                            if let definition {
                                Text(definition.muscles.map(\.title).joined(separator: " · "))
                                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                            }
                            Text("\(plan.setCount) sets · \(targetSummary)")
                                .font(FitTheme.medium(12)).foregroundStyle(FitTheme.dashboardAccent)
                            Label(expanded ? "Close set editor" : "Edit sets & reps", systemImage: expanded ? "chevron.up" : "slider.horizontal.3")
                                .font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44, alignment: .center).contentShape(Rectangle())
                }.buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier("routineExercise-\(plan.exerciseID)")
                    .accessibilityValue(expanded ? "Set editor expanded" : "Set editor collapsed")
                Menu {
                    Button("Replace exercise", systemImage: "arrow.triangle.2.circlepath", action: replace)
                    Button("Move up", systemImage: "arrow.up") { move(-1) }.disabled(!canMoveUp)
                    Button("Move down", systemImage: "arrow.down") { move(1) }.disabled(!canMoveDown)
                    Button("Remove exercise", role: .destructive) { removing = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                        .background(.white.opacity(0.035), in: Circle())
                }
                .accessibilityLabel("Options for \(definition?.name ?? "exercise")")
            }
            if expanded {
                Divider().overlay(.white.opacity(0.1))
                ExerciseImageButton(exercise: definition)
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(value: $plan.restSeconds, in: 0...3600, step: 15) {
                        Label("Default rest · \(plan.restSeconds)s", systemImage: "timer").font(FitTheme.medium(13))
                    }
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: 8) { restChoices }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { restChoices }
                            VStack(spacing: 8) { restChoices }
                        }
                    }
                }
                Label("Set targets", systemImage: "slider.horizontal.3")
                    .font(FitTheme.section(14)).padding(.top, 4)
                ForEach(targets) { $target in
                    let index = (plan.setTargets ?? []).firstIndex { $0.id == target.id } ?? 0
                    PlannedSetRow(target: $target, number: index + 1, kind: definition?.kind ?? .weighted, unit: unit,
                        duplicate: { duplicate(target.id) },
                        remove: { plan.setTargets?.removeAll { $0.id == target.id } },
                        move: { offset in moveSet(target.id, by: offset) },
                        canDelete: (plan.setTargets?.count ?? 0) > 1, canDuplicate: (plan.setTargets?.count ?? 0) < 40,
                        canMoveUp: index > 0, canMoveDown: index + 1 < (plan.setTargets?.count ?? 0))
                }
                Menu {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Button(type.rawValue) {
                            var value = plan.setTargets?.last?.duplicate() ?? PlannedSet()
                            value.type = type
                            plan.setTargets?.append(value)
                        }
                    }
                } label: {
                    Label("Add set", systemImage: "plus").font(FitTheme.button(13)).frame(maxWidth: .infinity, minHeight: 44)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(FitTheme.subtleBorder, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                }
                .disabled((plan.setTargets?.count ?? 0) >= 40)
                .accessibilityIdentifier("routineAddSet")
                DisclosureGroup("Exercise notes") {
                    TextField("Cues or reminders", text: $plan.notes, axis: .vertical).font(FitTheme.body(13)).padding(.top, 8)
                    if let instructions = definition?.instructions, !instructions.isEmpty {
                        Text(instructions).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary).padding(.top, 8)
                    }
                }.font(FitTheme.medium(13))
            }
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 22), highlighted: expanded)
        .confirmationDialog("Remove \(definition?.name ?? "this exercise")?", isPresented: $removing, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive, action: remove)
        }
    }
    private var restChoices: some View {
        ForEach([30, 60, 90, 120], id: \.self) { seconds in
            Button { plan.restSeconds = seconds } label: {
                Text("\(seconds)s").font(FitTheme.medium(12)).monospacedDigit()
                    .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(plan.restSeconds == seconds ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                    .background(plan.restSeconds == seconds ? FitTheme.dashboardAccent.opacity(0.1) : FitTheme.dashboardBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(RoutineEditorPressStyle())
            .accessibilityLabel("Set default rest to \(seconds) seconds")
            .accessibilityAddTraits(plan.restSeconds == seconds ? .isSelected : [])
        }
    }
    private func duplicate(_ id: UUID) {
        guard var values = plan.setTargets, values.count < 40, let index = values.firstIndex(where: { $0.id == id }) else { return }
        values.insert(values[index].duplicate(), at: index + 1); plan.setTargets = values
    }
    private func moveSet(_ id: UUID, by offset: Int) {
        guard var values = plan.setTargets, let index = values.firstIndex(where: { $0.id == id }), values.indices.contains(index + offset) else { return }
        values.swapAt(index, index + offset); plan.setTargets = values
    }
}

private struct PlannedSetRow: View {
    @Binding var target: PlannedSet
    let number: Int
    let kind: ExerciseKind
    let unit: WeightUnit
    let duplicate: () -> Void
    let remove: () -> Void
    let move: (Int) -> Void
    let canDelete: Bool
    let canDuplicate: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var fieldLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(number)").font(FitTheme.metric(13)).foregroundStyle(FitTheme.dashboardAccent)
                    .frame(width: 32, height: 32)
                    .background(FitTheme.dashboardAccent.opacity(0.1), in: Circle())
                    .accessibilityLabel("Set \(number)")
                Picker("Set \(number) type", selection: $target.type) {
                    ForEach(SetType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).font(FitTheme.medium(12)).labelsHidden()
                Spacer(minLength: 0)
                Menu {
                    Button("Duplicate set", action: duplicate).disabled(!canDuplicate)
                    Button("Move up") { move(-1) }.disabled(!canMoveUp)
                    Button("Move down") { move(1) }.disabled(!canMoveDown)
                    Button("Delete set", role: .destructive, action: remove).disabled(!canDelete)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel("Options for set \(number)")
            }
            if kind == .duration {
                RoutineNumberField(title: "Seconds", value: Binding(get: { target.seconds }, set: { target.seconds = $0 ?? 0 }))
            } else {
                fieldLayout {
                    RoutineNumberField(title: "Min reps", value: integer($target.repMin), integer: true)
                    RoutineNumberField(title: "Max reps", value: integer($target.repMax), integer: true)
                    if kind == .weighted {
                        RoutineNumberField(title: unit.rawValue, value: Binding(get: { target.loadKG.map { unit.display($0) } }, set: { target.loadKG = $0.map { unit.kilograms($0) } }))
                    }
                }
            }
            DisclosureGroup("Rest & effort (optional)") {
                fieldLayout {
                    RoutineNumberField(title: "Rest, seconds", value: Binding(get: { target.restSeconds.map(Double.init) }, set: { value in
                        if let value, value.isFinite, abs(value) < 100_000 { target.restSeconds = Int(value) }
                        else if value == nil { target.restSeconds = nil }
                    }), integer: true)
                    RoutineNumberField(title: "Target RPE", value: $target.targetRPE)
                }.padding(.top, 10)
                if kind == .duration {
                    RoutineNumberField(title: "Distance, meters", value: Binding(get: { target.distanceMeters == 0 ? nil : target.distanceMeters }, set: { target.distanceMeters = $0 ?? 0 }))
                        .padding(.top, 10)
                }
                Text("Blank rest uses the exercise default. RPE measures effort from 1 (easy) to 10 (maximum). Targets stay separate from effort you log during training.")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary).padding(.top, 8)
            }.font(FitTheme.medium(12))
            if !target.isValid || (kind == .duration && target.seconds <= 0) {
                Text("Check this set’s targets. Reps must be 1–100, rest 0–3600s, and RPE 1–10.")
                    .font(FitTheme.body(11)).foregroundStyle(.orange)
            }
        }
        .padding(12)
        .background(FitTheme.dashboardBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.05), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }
    private func integer(_ value: Binding<Int>) -> Binding<Double?> {
        Binding(get: { Double(value.wrappedValue) }, set: { new in
            if let new, new.isFinite, abs(new) < 100_000 { value.wrappedValue = Int(new) }
        })
    }
}

private struct RoutineNumberField: View {
    let title: String
    @Binding var value: Double?
    var integer = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
            TextField("—", value: $value, format: .number.precision(.fractionLength(0...2)))
                .font(FitTheme.strong(18)).monospacedDigit().multilineTextAlignment(.center)
                .keyboardType(integer ? .numberPad : .decimalPad)
                .focused($focused)
                .padding(.horizontal, 10).frame(minHeight: 48)
                .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(focused ? FitTheme.dashboardAccent : FitTheme.subtleBorder, lineWidth: 1) }
                .accessibilityLabel(title)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoutineExercisePicker: View {
    let store: GymStore
    let multiple: Bool
    let onSelect: ([ExerciseDefinition]) -> Void
    var body: some View {
        NavigationStack {
            ExerciseBrowser(store: store, title: multiple ? "Add exercises" : "Replace exercise",
                            mode: multiple ? .multiple : .single,
                            selectionHint: multiple ? nil : "Changing the tracking type resets set targets for this exercise.", onSelect: onSelect)
        }
    }
}

struct RoutineDayDestinationSheet: View {
    let routine: Routine
    let source: Int
    let moving: Bool
    let onSelect: (Int) -> Void
    @State private var replacing: Int?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(moving ? "The two days swap places, keeping both workouts." : "Copies are independent. Editing one day will not change another.")
                        .font(FitTheme.body(13)).foregroundStyle(.secondary)
                    ForEach(routine.days.sorted { $0.weekday < $1.weekday }.filter { $0.weekday != source }) { day in
                        Button {
                            if !moving && !day.exercises.isEmpty { replacing = day.weekday }
                            else { onSelect(day.weekday) }
                        } label: {
                            LabeledContent(RoutineSchedule.weekdays[day.weekday], value: day.kind == .workout ? day.title : day.kind == .rest ? "Rest" : "Unassigned")
                        }
                    }
                }
            }.navigationTitle(moving ? "Move workout" : "Copy workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .confirmationDialog("Replace this day’s workout?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), titleVisibility: .visible) {
                    Button("Replace workout", role: .destructive) { if let replacing { onSelect(replacing) } }
                }
        }.presentationDetents([.medium, .large]).tint(FitTheme.dashboardAccent)
    }
}

struct RoutineReuseSheet: View {
    let store: GymStore
    let onSelect: (RoutineDay) -> Void
    @State private var deleting: UUID?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.orange) }
                if store.savedWorkouts.isEmpty && store.routines.flatMap(\.trainingDays).isEmpty {
                    ContentUnavailableView("No saved workouts yet", systemImage: "bookmark", description: Text("Add exercises to a day, then use Save workout for reuse in its options."))
                }
                if !store.savedWorkouts.isEmpty {
                    Section("Saved workouts") {
                        ForEach(store.savedWorkouts) { saved in
                            Button { onSelect(saved.day) } label: { workoutLabel(saved.day) }
                                .swipeActions { Button("Delete", role: .destructive) { deleting = saved.id } }
                        }
                    }
                }
                ForEach(store.routines) { routine in
                    if !routine.trainingDays.isEmpty {
                        Section(routine.name) {
                            ForEach(routine.trainingDays.filter { !$0.exercises.isEmpty }) { day in
                                Button { onSelect(day) } label: { workoutLabel(day) }
                            }
                        }
                    }
                }
            }.navigationTitle("Reuse a workout").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .confirmationDialog("Delete this saved workout?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Delete saved workout", role: .destructive) { if let deleting { store.deleteSavedWorkout(deleting) }; deleting = nil }
                }
        }.tint(FitTheme.dashboardAccent)
    }
    private func workoutLabel(_ day: RoutineDay) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.title).font(FitTheme.section(15))
            Text("\(day.exercises.count) exercises").font(FitTheme.body(12)).foregroundStyle(.secondary)
        }.padding(.vertical, 5)
    }
}

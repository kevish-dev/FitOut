import SwiftUI

struct RoutineEditor: View {
    let store: GymStore
    @State var routine: Routine
    var initialWeekday: Int? = nil
    var initialStage: RoutineEditorStage? = nil
    var unit: WeightUnit = .kg
    @State private var stage: RoutineEditorStage = .schedule
    @State private var weekday = 0
    @State private var otherDays: RoutineDayKind? = .flexible
    @State private var restored = false
    @State private var loaded = false
    @State private var finished = false
    @State private var message: String?
    @State private var issue: String?
    @State private var sheet: RoutineBuilderSheet?
    @State private var pendingCopy: RoutineDayReplacement?
    @State private var pendingReuse: RoutineDayReplacement?
    @State private var discard = false
    @State private var keyboardIsVisible = false
    @State private var contentPosition = ScrollPosition(edge: .top)
    @State private var visibleWeekday: Int?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var draft: RoutineDraft { RoutineDraft(routine: routine, stage: stage, weekday: weekday, updatedAt: .distantPast) }
    private var selectedDay: RoutineDay? { routine.days.first { $0.weekday == weekday } }
    private var scheduleIsReady: Bool {
        !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !routine.trainingDays.isEmpty
    }
    private var isNewRoutine: Bool { !store.routines.contains { $0.id == routine.id } }
    private var draftIsStored: Bool {
        guard let saved = store.drafts.first(where: { $0.id == routine.id }) else { return false }
        return saved.hasSameContent(as: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                    if restored { status("Unsaved draft restored", symbol: "arrow.counterclockwise") }
                    if let message { status(message, symbol: "checkmark.circle") }
                    if let issue {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(FitTheme.body(13)).foregroundStyle(.orange)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("routineValidation")
                    }
                    switch stage {
                    case .schedule: schedule
                    case .workouts: workout
                    case .review: review
                    }
                }
                .frame(maxWidth: 560)
                .padding(FitTheme.pageInset)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($contentPosition)
            .safeAreaInset(edge: .top, spacing: 0) {
                RoutineStageBar(selection: $stage)
                    .padding(.horizontal, FitTheme.pageInset).padding(.vertical, 10)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
                    .background(FitTheme.dashboardBackground)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(FitTheme.dashboardBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer.workoutControlClearance("routine.editor.actions") }
            .navigationTitle(isNewRoutine ? "Create routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { keepDraftAndClose() }.accessibilityIdentifier("closeRoutine") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Discard unsaved changes", role: .destructive) { discard = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Routine options")
                }
            }
        }
        .tint(FitTheme.dashboardAccent)
        .foregroundStyle(FitTheme.textPrimary)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(FitTheme.dashboardBackground)

        .onAppear(perform: restoreDraft)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardIsVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardIsVisible = false }
        .task(id: draft) {
            guard loaded, !finished else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !finished, !Task.isCancelled else { return }
            persistDraft()
        }
        .onDisappear { if loaded && !finished { persistDraft() } }
        .onChange(of: scenePhase) { _, value in if value != .active && loaded && !finished { persistDraft() } }
        .onChange(of: stage) { _, value in
            issue = nil; message = nil; dismissKeyboard()
            contentPosition.scrollTo(edge: .top)
            visibleWeekday = weekday
            if value == .schedule { synchronizeOtherDays() }
        }
        .onChange(of: weekday) { _, value in visibleWeekday = value; dismissKeyboard() }
        .interactiveDismissDisabled(loaded && !finished && !draftIsStored)
        .sheet(item: $sheet, onDismiss: {
            if let source = pendingReuse { pendingCopy = source; pendingReuse = nil }
        }) { route in builderSheet(route) }
        .confirmationDialog("Replace this day’s workout?", isPresented: Binding(get: { pendingCopy != nil }, set: { if !$0 { pendingCopy = nil } }), titleVisibility: .visible) {
            Button("Replace workout", role: .destructive) {
                if let request = pendingCopy, let target = routine.days.first(where: { $0.id == request.targetID }) {
                    RoutineSchedule.copy(request.source, to: target.weekday, in: &routine)
                }
                pendingCopy = nil
            }
            Button("Cancel", role: .cancel) { pendingCopy = nil }
        } message: { Text("The selected day's workout will be replaced. Saved history is kept.") }
        .confirmationDialog("Discard this draft?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) {
                if store.discardDraft(routine.id) { finished = true; dismiss() }
                else { issue = store.error }
            }
        } message: { Text("Your saved routine and completed workouts stay unchanged.") }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            RoutinePlanHero(routine: routine)
            VStack(alignment: .leading, spacing: 8) {
                Text("Routine name").font(FitTheme.medium(13)).foregroundStyle(FitTheme.textSecondary)
                TextField("e.g. My strength plan", text: $routine.name).font(FitTheme.section(18))
                    .textInputAutocapitalization(.words).submitLabel(.done).focused($nameFocused)
                    .onSubmit { nameFocused = false }
                    .padding(FitTheme.cardInset)
                    .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14).strokeBorder(nameFocused ? FitTheme.dashboardAccent : FitTheme.subtleBorder, lineWidth: 1)
                    }
                    .accessibilityIdentifier("routineName")
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Training days", systemImage: "calendar").font(FitTheme.section(16))
                    Spacer()
                    Text("\(routine.trainingDays.count) / 7").font(FitTheme.medium(12)).monospacedDigit()
                        .foregroundStyle(FitTheme.dashboardAccent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(FitTheme.dashboardAccent.opacity(0.1), in: Capsule())
                }
                trainingDayPicker
                HStack(spacing: 12) {
                    Image(systemName: otherDays == .rest ? "moon" : "circle.dashed")
                        .foregroundStyle(FitTheme.dashboardAccent).frame(width: 26)
                    Text("Other days").font(FitTheme.medium(14))
                    Spacer(minLength: 0)
                    Picker("Other days", selection: $otherDays) {
                        Text("Keep as set").tag(nil as RoutineDayKind?)
                        Text("Open").tag(Optional(RoutineDayKind.flexible))
                        Text("Rest").tag(Optional(RoutineDayKind.rest))
                    }.pickerStyle(.menu).labelsHidden().font(FitTheme.medium(13))
                    .onChange(of: otherDays) { _, kind in
                        guard let kind else { return }
                        for index in routine.days.indices where routine.days[index].kind != .workout { routine.days[index].kind = kind }
                    }
                }.padding(.horizontal, 14).frame(minHeight: 54)
                    .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                Text(otherDays == .rest ? "Unselected days are marked as rest." : otherDays == .flexible ? "Open days have no scheduled workout." : "Each day keeps its current open or rest setting.")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }
            DisclosureGroup {
                Toggle("Start on a specific day", isOn: Binding(get: { routine.startsOn != nil }, set: { routine.startsOn = $0 ? Calendar.current.startOfDay(for: .now) : nil }))
                if routine.startsOn != nil {
                    DatePicker("Starts", selection: Binding(get: { routine.startsOn ?? .now }, set: { routine.startsOn = $0 }), displayedComponents: .date)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock").font(.system(size: 21)).foregroundStyle(FitTheme.dashboardAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start date").font(FitTheme.medium(14))
                        Text(routine.startsOn.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Whenever you're ready")
                            .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                    }
                }.frame(minHeight: 40)
            }.font(FitTheme.body(14)).routinePanel()
        }
    }

    @ViewBuilder private var trainingDayPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) { ForEach(0..<7, id: \.self) { trainingDay($0) } }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ForEach(0..<7, id: \.self) { trainingDay($0) } }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(0..<7, id: \.self) { trainingDay($0) }
                }
            }
        }
    }

    private func trainingDay(_ index: Int) -> some View {
        let selected = routine.days.first { $0.weekday == index }?.kind == .workout
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { toggleDay(index) }
            issue = nil
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack {
                        Text(RoutineSchedule.weekdays[index]).font(FitTheme.medium(14))
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    }.padding(.horizontal, 16)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: selected ? "dumbbell.fill" : "plus")
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 44, height: 44)
                            .dashboardGlass(in: Circle(), highlighted: selected, interactive: true)
                            .overlay { Circle().strokeBorder(selected ? FitTheme.dashboardAccent.opacity(0.55) : .clear, lineWidth: 1) }
                        Text(String(RoutineSchedule.weekdays[index].prefix(3))).font(FitTheme.medium(11))
                    }
                }
            }
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 68)
            .foregroundStyle(selected ? FitTheme.dashboardAccent : FitTheme.textSecondary)
            .background {
                if dynamicTypeSize.isAccessibilitySize {
                    RoundedRectangle(cornerRadius: 14).fill(FitTheme.surface)
                }
            }
        }
        .buttonStyle(RoutineEditorPressStyle())
        .accessibilityLabel(RoutineSchedule.weekdays[index])
        .accessibilityValue(selected ? "Training day" : "Not a training day")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("routineTrainingDay-\(index)")
    }

    private var workout: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        Button {
                            guard weekday != index else { return }
                            dismissKeyboard(); weekday = index; message = nil; issue = nil
                        } label: {
                            VStack(spacing: 8) {
                                Text(String(RoutineSchedule.weekdays[index].prefix(3))).font(FitTheme.medium(12))
                                Image(systemName: (routine.days.first { $0.weekday == index }?.kind ?? .flexible).editorSymbol)
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .frame(minWidth: 50, minHeight: 68)
                            .foregroundStyle(weekday == index ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                            .dashboardGlass(in: RoundedRectangle(cornerRadius: 16), highlighted: weekday == index, interactive: true)
                        }.buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier("routineEditDay-\(index)").id(index)
                            .accessibilityLabel(RoutineSchedule.weekdays[index])
                            .accessibilityAddTraits(weekday == index ? .isSelected : [])
                    }
                }.scrollTargetLayout().padding(.vertical, 2)
            }
            .scrollPosition(id: $visibleWeekday, anchor: .center)
            if let day = selectedDay {
                workoutDay(day).id(day.id)
            } else {
                ContentUnavailableView("Day unavailable", systemImage: "calendar.badge.exclamationmark",
                    description: Text("This draft has no entry for the selected day. Choose another day or close the editor; your saved routine is preserved."))
            }
        }
    }

    private func workoutDay(_ day: RoutineDay) -> some View {
        let selected = $routine.days.identifiedElement(id: day.id, fallback: day)
        return VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack {
                Text(RoutineSchedule.weekdays[day.weekday]).font(FitTheme.section(23))
                Spacer()
                Menu {
                    Button("Use a saved workout", systemImage: "square.stack") { openSheet(.reuse, dayID: day.id) }
                    if day.kind == .workout {
                        Button("Copy to another day", systemImage: "doc.on.doc") { openSheet(.copy, dayID: day.id) }
                        Button("Move to another day", systemImage: "arrow.left.arrow.right") { openSheet(.move, dayID: day.id) }
                        Button("Save workout for reuse", systemImage: "bookmark") {
                            if store.saveWorkout(day) { message = "Saved to reusable workouts" } else { issue = store.error }
                        }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).dashboardGlass(in: Circle(), interactive: true) }
                .accessibilityLabel("Workout options")
            }
            RoutineDayKindControl(selection: Binding(get: { selected.wrappedValue.kind }, set: { kind in
                var value = selected.wrappedValue; value.kind = kind
                if kind == .workout && value.title.isEmpty { value.title = "\(RoutineSchedule.weekdays[value.weekday]) workout" }
                selected.wrappedValue = value
            }))
            if day.kind == .workout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workout name").font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
                    HStack(spacing: 10) {
                        TextField("e.g. Chest & triceps", text: selected.title)
                            .font(FitTheme.section(19)).accessibilityIdentifier("routineWorkoutName")
                        Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(FitTheme.textSecondary).accessibilityHidden(true)
                    }.padding(FitTheme.cardInset)
                        .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
                if !day.exercises.isEmpty {
                    HStack {
                        Text("Exercises").font(FitTheme.section(17))
                        Spacer()
                        Text("\(day.exercises.count) movements · \(day.exercises.reduce(0) { $0 + $1.setCount }) sets")
                            .font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
                    }.padding(.top, 4)
                }
                LazyVStack(spacing: FitTheme.sectionSpacing) {
                    ForEach(day.exercises) { plan in
                        RoutineExerciseCard(plan: selected.exercises.identifiedElement(id: plan.id, fallback: plan), definition: store.exercise(plan.exerciseID), unit: unit,
                            canMoveUp: day.exercises.first?.id != plan.id, canMoveDown: day.exercises.last?.id != plan.id,
                            replace: { openSheet(.replace(plan.id), dayID: day.id) },
                            remove: { selected.wrappedValue.exercises.removeAll { $0.id == plan.id } },
                            move: { offset in moveExercise(plan.id, in: day.id, by: offset) })
                        .draggable(plan.id.uuidString)
                        .dropDestination(for: String.self) { ids, _ in
                            guard let dayIndex = routine.days.firstIndex(where: { $0.id == day.id }),
                                  let id = ids.first.flatMap(UUID.init(uuidString:)),
                                  let from = routine.days[dayIndex].exercises.firstIndex(where: { $0.id == id }),
                                  let to = routine.days[dayIndex].exercises.firstIndex(where: { $0.id == plan.id }), from != to else { return false }
                            routine.days[dayIndex].exercises.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                            return true
                        }
                    }
                }
                Button { openSheet(.add, dayID: day.id) } label: {
                    VStack(spacing: 12) {
                        if day.exercises.isEmpty {
                            Image("RoutineEquipment").resizable().scaledToFit().frame(height: 120).accessibilityHidden(true)
                            Text("Start with your first movement").font(FitTheme.section(17))
                            Text("Choose exercises from the library or add your own.")
                                .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary).multilineTextAlignment(.center)
                        }
                        Label("Add exercises", systemImage: "plus.circle.fill").font(FitTheme.button(15))
                            .foregroundStyle(FitTheme.dashboardAccent)
                    }
                    .padding(FitTheme.cardInset).frame(maxWidth: .infinity, minHeight: 54)
                    .dashboardGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
                }.buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier("routineAddExercises")
                DisclosureGroup("Workout details") {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Notes (optional)", text: Binding(get: { selected.wrappedValue.notes ?? "" }, set: { selected.wrappedValue.notes = $0 }), axis: .vertical)
                        Toggle("Duration target", isOn: Binding(get: { selected.wrappedValue.durationMinutes != nil }, set: { selected.wrappedValue.durationMinutes = $0 ? 45 : nil }))
                        if day.durationMinutes != nil {
                            Stepper("\(day.durationMinutes ?? 45) minutes", value: Binding(get: { selected.wrappedValue.durationMinutes ?? 45 }, set: { selected.wrappedValue.durationMinutes = $0 }), in: 1...600, step: 5)
                        }
                        Button { openSheet(.muscles, dayID: day.id) } label: {
                            Label(day.muscles.isEmpty ? "Choose focus muscles" : day.muscles.map(\.title).joined(separator: ", "), systemImage: "figure.strengthtraining.traditional")
                        }
                    }.padding(.top, 12)
                }.font(FitTheme.body(14)).routinePanel()
            } else {
                RoutineDayPauseGraphic(kind: day.kind, hasExercises: !day.exercises.isEmpty)
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            RoutinePlanHero(routine: routine, reviewing: true)
            HStack {
                Text(routine.name.isEmpty ? "Review your routine" : routine.name).font(FitTheme.section(19))
                Spacer()
                Image(systemName: "repeat").foregroundStyle(FitTheme.dashboardAccent)
            }
            Text("Tap a day to make changes.").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
            ForEach(routine.days.sorted { $0.weekday < $1.weekday }) { day in
                Button { weekday = day.weekday; stage = .workouts } label: {
                    RoutineReviewDay(day: day, exercise: day.exercises.first.flatMap { store.exercise($0.exerciseID) })
                }.buttonStyle(RoutineEditorPressStyle())
            }
            Toggle(routine.archivedAt == nil ? "Use as active routine" : "Restore and use as active", isOn: Binding(get: { routine.isActive }, set: { value in
                routine.isActive = value
                if value { routine.archivedAt = nil }
            })).font(FitTheme.body(14)).routinePanel()
            if let start = routine.startsOn {
                Text("Starts \(start.formatted(date: .abbreviated, time: .omitted))").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
            }
            if let error = store.readinessError(for: routine) {
                Label(error, systemImage: "exclamationmark.circle").font(FitTheme.body(13)).foregroundStyle(.orange)
                    .accessibilityIdentifier("routineReadiness")
            } else {
                Text("Ready to save. Your completed workout history stays unchanged.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stage == .schedule && !keyboardIsVisible {
                Text(routine.trainingDays.isEmpty ? "Select at least one training day to continue." : routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Add a routine name to continue." : "\(routine.trainingDays.count) training \(routine.trainingDays.count == 1 ? "day" : "days") selected · Exercises are next")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { footerActions }
            } else {
                HStack(alignment: .center, spacing: 12) { footerActions }
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, FitTheme.pageInset).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder private var footerActions: some View {
        if keyboardIsVisible {
            Button(action: dismissKeyboard) {
                Text("Done").font(FitTheme.button(15))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 54)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                    .dashboardGlass(in: RoundedRectangle(cornerRadius: 16), interactive: true)
            }
            .buttonStyle(RoutineEditorPressStyle())
            .accessibilityLabel("Done editing")
            .accessibilityIdentifier("routineKeyboardDone")
        } else if stage != .schedule {
            Button { stage = stage == .review ? .workouts : .schedule } label: {
                Image(systemName: "arrow.left").frame(width: 54, height: 54).dashboardGlass(in: Circle(), interactive: true)
            }.buttonStyle(.fitPlain).accessibilityLabel("Previous step")
        }
        Button(action: advance) {
            HStack(spacing: 10) {
                Text(stage == .review ? "Save routine" : stage == .schedule ? "Choose exercises" : "Review routine")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: stage == .review ? "checkmark" : "arrow.right")
            }
            .font(FitTheme.button(15)).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
                .background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RoutineEditorPressStyle())
        .disabled(stage == .schedule && !scheduleIsReady)
        .opacity(stage == .schedule && !scheduleIsReady ? 0.45 : 1)
        .accessibilityIdentifier(stage == .review ? "saveRoutine" : "routineContinue")
    }

    private func dismissKeyboard() {
        nameFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func openSheet(_ action: RoutineBuilderSheet.Action, dayID: UUID) {
        guard sheet == nil, routine.days.contains(where: { $0.id == dayID }) else { return }
        dismissKeyboard()
        sheet = RoutineBuilderSheet(dayID: dayID, action: action)
    }

    @ViewBuilder private func builderSheet(_ route: RoutineBuilderSheet) -> some View {
        if let day = route.targetDay(in: routine) {
            switch route.action {
            case .add, .replace:
                RoutineExercisePicker(store: store, multiple: route.action == .add) { selected in
                    defer { sheet = nil }
                    guard let dayIndex = routine.days.firstIndex(where: { $0.id == route.dayID }) else { return }
                    if case .replace(let id) = route.action {
                        guard let exercise = selected.first,
                              let index = routine.days[dayIndex].exercises.firstIndex(where: { $0.id == id }) else {
                            issue = "This exercise changed. Reopen it before replacing it."; return
                        }
                        let previousKind = store.exercise(routine.days[dayIndex].exercises[index].exerciseID)?.kind
                        routine.days[dayIndex].exercises[index].exerciseID = exercise.id
                        if previousKind != exercise.kind { routine.days[dayIndex].exercises[index].setTargets = PlannedExercise.make(for: exercise).resolvedSets }
                    } else {
                        routine.days[dayIndex].exercises.append(contentsOf: selected.map { PlannedExercise.make(for: $0) })
                    }
                }
            case .reuse:
                RoutineReuseSheet(store: store) { source in
                    defer { sheet = nil }
                    guard let target = route.targetDay(in: routine) else { return }
                    if !target.exercises.isEmpty { pendingReuse = RoutineDayReplacement(source: source, targetID: route.dayID) }
                    else { RoutineSchedule.copy(source, to: target.weekday, in: &routine) }
                }
            case .copy, .move:
                RoutineDayDestinationSheet(routine: routine, source: day.weekday, moving: route.action == .move) { target in
                    defer { sheet = nil }
                    guard let source = route.targetDay(in: routine) else { return }
                    if route.action == .move { RoutineSchedule.move(dayID: source.id, to: target, in: &routine); weekday = target }
                    else { RoutineSchedule.copy(source, to: target, in: &routine) }
                }
            case .muscles:
                NavigationStack {
                    MuscleMapView(selection: $routine.days.identifiedElement(id: day.id, fallback: day).muscles)
                        .toolbar { Button("Done") { sheet = nil } }
                }
            }
        } else {
            NavigationStack {
                ContentUnavailableView("Day unavailable", systemImage: "calendar.badge.exclamationmark",
                    description: Text("Close this panel and choose an available day. Your changes are preserved."))
                    .toolbar { Button("Close") { sheet = nil } }
            }
        }
    }

    private func restoreDraft() {
        guard !loaded else { return }
        let saved = store.drafts.first(where: { $0.id == routine.id })
        if let saved {
            routine = saved.routine; restored = true
            if let committed = store.routines.first(where: { $0.id == routine.id }) {
                routine.archivedAt = committed.archivedAt; routine.isActive = committed.isActive
            }
        }
        let entry = RoutineEditorEntry.resolve(isSaved: store.routines.contains(where: { $0.id == routine.id }), draft: saved,
            initialWeekday: initialWeekday, initialStage: initialStage)
        stage = entry.stage; weekday = entry.weekday
        visibleWeekday = weekday
        synchronizeOtherDays()
        loaded = true
    }
    private func persistDraft() {
        if !store.saveDraft(draft) { issue = store.error }
    }
    private func keepDraftAndClose() {
        if store.saveDraft(draft) { finished = true; dismiss() } else { issue = store.error }
    }
    private func advance() {
        dismissKeyboard()
        issue = nil
        switch stage {
        case .schedule:
            guard !routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issue = "Give your routine a name."; return }
            guard let first = routine.trainingDays.first else { issue = "Choose at least one training day."; return }
            weekday = first.weekday; stage = .workouts
        case .workouts: stage = .review
        case .review:
            if let error = store.readinessError(for: routine) { issue = error; return }
            if store.save(routine, discardDraft: true) { finished = true; dismiss() } else { issue = store.error }
        }
    }
    private func toggleDay(_ weekday: Int) {
        guard let index = routine.days.firstIndex(where: { $0.weekday == weekday }) else { return }
        routine.days[index].kind = routine.days[index].kind == .workout ? (otherDays ?? .flexible) : .workout
        if routine.days[index].kind == .workout && routine.days[index].title.isEmpty {
            routine.days[index].title = "\(RoutineSchedule.weekdays[weekday]) workout"
        }
    }
    private func synchronizeOtherDays() {
        let kinds = Set(routine.days.filter { $0.kind != .workout }.map(\.kind))
        otherDays = kinds.count == 1 ? kinds.first : nil
    }
    private func moveExercise(_ id: UUID, in dayID: UUID, by offset: Int) {
        guard let dayIndex = routine.days.firstIndex(where: { $0.id == dayID }),
              let from = routine.days[dayIndex].exercises.firstIndex(where: { $0.id == id }),
              routine.days[dayIndex].exercises.indices.contains(from + offset) else { return }
        routine.days[dayIndex].exercises.swapAt(from, from + offset)
    }
    private func status(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct RoutineBuilderSheet: Hashable, Identifiable {
    enum Action: Hashable { case add, replace(UUID), reuse, copy, move, muscles }
    let dayID: UUID
    let action: Action
    var id: Self { self }
    func targetDay(in routine: Routine) -> RoutineDay? { routine.days.first { $0.id == dayID } }
}

private struct RoutineDayReplacement {
    let source: RoutineDay
    let targetID: UUID
}

extension View {
    func routinePanel() -> some View {
        padding(FitTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
            .dashboardGlass(in: RoundedRectangle(cornerRadius: 18))
    }
}

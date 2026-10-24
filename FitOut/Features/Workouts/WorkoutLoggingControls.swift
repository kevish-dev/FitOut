import SwiftUI

struct WorkoutExerciseCard: View {
    let entry: WorkoutEntry
    @Binding var expanded: Bool
    let unit: WeightUnit
    let session: WorkoutSession
    let canComplete: Bool
    let reference: (UUID) -> WorkoutSetReference?
    let reuse: (UUID) -> Void
    let repeatInputs: (UUID) -> Void
    let binding: (UUID) -> Binding<WorkoutSet>
    let complete: (UUID) -> Void
    let start: (UUID) -> Void
    let stopTimer: (UUID) -> Void
    let deleteSet: (UUID) -> Void
    let addSet: () -> Void
    let notes: Binding<String>
    let replace: () -> Void
    let toggleSkip: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var logged: Int { entry.sets.filter { $0.completedAt != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 4) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        ExerciseArtwork(exercise: entry.exercise, size: typeSize.isAccessibilitySize ? 44 : 74)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(entry.exercise.name).font(FitTheme.section(16))
                            Text(entry.exercise.muscles.map(\.title).joined(separator: " · "))
                                .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                            Label(entry.skipped ? "Skipped" : "\(logged)/\(entry.sets.count) sets logged", systemImage: entry.skipped ? "forward.end" : "checkmark.circle")
                                .font(FitTheme.medium(12)).foregroundStyle(FitTheme.dashboardAccent)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(FitTheme.textSecondary)
                    }.frame(maxWidth: .infinity, minHeight: 74).contentShape(Rectangle())
                }.buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier("workoutEntry-\(entry.id)")
                    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                Menu {
                    Button("Replace exercise", systemImage: "arrow.triangle.2.circlepath", action: replace).disabled(logged > 0)
                    Button(entry.skipped ? "Restore exercise" : "Skip exercise", systemImage: entry.skipped ? "arrow.uturn.backward" : "forward.end", action: toggleSkip)
                } label: { Image(systemName: "ellipsis").foregroundStyle(FitTheme.textSecondary).frame(width: 44, height: 44) }
                .accessibilityLabel("Options for \(entry.exercise.name)")
            }
            if expanded {
                Divider().overlay(FitTheme.textPrimary.opacity(0.05))
                if entry.skipped {
                    Text("Previously logged sets are kept.").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                    Button("Restore exercise", action: toggleSkip).font(FitTheme.button(14)).frame(minHeight: 44)
                } else {
                    ExerciseImageButton(exercise: entry.exercise)
                    ForEach(Array(entry.sets.enumerated()), id: \.element.id) { index, set in
                        WorkoutSetEditor(value: binding(set.id), kind: entry.exercise.kind, unit: unit,
                            number: index + 1, canComplete: canComplete, session: session,
                            previous: reference(set.id), reuse: { reuse(set.id) },
                            repeatInputs: { repeatInputs(set.id) }, canRepeat: entry.sets.dropFirst(index + 1).contains { $0.type == set.type && $0.completedAt == nil && $0.startedAt == nil },
                            start: { start(set.id) }, stopTimer: { stopTimer(set.id) }, complete: { complete(set.id) }, delete: { deleteSet(set.id) })
                    }
                    Button(action: addSet) {
                        Label("Add set", systemImage: "plus").font(FitTheme.button(13)).frame(maxWidth: .infinity, minHeight: 48)
                            .background(FitTheme.textPrimary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(FitTheme.subtleBorder, style: StrokeStyle(lineWidth: 1, dash: [4])) }
                    }.buttonStyle(RoutineEditorPressStyle())
                    DisclosureGroup("Exercise notes") {
                        TextField("Cues or reminders", text: notes, axis: .vertical).font(FitTheme.body(13)).padding(.top, 8)
                    }.font(FitTheme.medium(12))
                }
            }
        }
        .padding(FitTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 23), highlighted: expanded && !entry.skipped)
    }
}

struct WorkoutSetEditor: View {
    @Binding var value: WorkoutSet
    let kind: ExerciseKind
    let unit: WeightUnit
    let number: Int
    let canComplete: Bool
    let session: WorkoutSession
    let previous: WorkoutSetReference?
    let reuse: () -> Void
    let repeatInputs: () -> Void
    let canRepeat: Bool
    let start: () -> Void
    let stopTimer: () -> Void
    let complete: () -> Void
    let delete: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isLogged: Bool { value.completedAt != nil }
    private var canLog: Bool { value.isValid && (kind == .duration ? value.seconds > 0 || (value.startedAt != nil && value.timedActiveSeconds == nil) : value.reps > 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Set \(number)").font(FitTheme.section(13))
                if isLogged { Image(systemName: "checkmark.seal.fill").foregroundStyle(FitTheme.dashboardAccent).accessibilityHidden(true) }
                Spacer(minLength: 0)
                Menu {
                    Picker("Set type", selection: $value.type) { ForEach(SetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Button(kind == .weighted ? "Apply weight to remaining sets" : "Repeat inputs to remaining sets", systemImage: "arrow.down.to.line", action: repeatInputs)
                        .disabled(!canRepeat || !value.isValid || (kind == .duration && (value.seconds <= 0 || (value.startedAt != nil && value.timedActiveSeconds == nil))))
                    if !isLogged {
                        if value.startedAt != nil && value.timedActiveSeconds == nil { Button("Stop set timer", systemImage: "stopwatch", action: stopTimer) }
                        else { Button(value.startedAt == nil ? "Start set timer" : "Restart set timer", systemImage: "stopwatch", action: start).disabled(!canComplete) }
                    }
                    Button("Delete set", role: .destructive, action: delete)
                } label: { Label(value.type.rawValue, systemImage: "chevron.down").font(FitTheme.medium(11)).frame(minHeight: 44) }
                .accessibilityLabel("Options for set \(number), \(value.type.rawValue)")
            }
            if let previous {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) { previousValues(previous); Spacer(minLength: 0); reuseAction }
                    VStack(alignment: .leading, spacing: 4) { previousValues(previous); reuseAction }
                }
            }
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { setFields(stacked: true) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 8) { setFields(stacked: false) }
                    VStack(alignment: .leading, spacing: 10) { setFields(stacked: true) }
                }
            }
            if !canLog && !isLogged {
                Text(kind == .duration ? "Enter a positive duration to log this set." : "Enter positive reps to log this set.")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            if let target = value.plannedTarget {
                Text(targetSummary(target)).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            if value.startedAt != nil {
                ViewThatFits(in: .horizontal) {
                    HStack { WorkoutSetClock(session: session, set: value); Spacer(minLength: 8); timerAction }
                    VStack(alignment: .leading, spacing: 4) { WorkoutSetClock(session: session, set: value); timerAction }
                }
            }
            else if !isLogged {
                Button("Start set timer", systemImage: "stopwatch", action: start)
                    .font(FitTheme.medium(12)).frame(minHeight: 44).disabled(!canComplete)
            }
            DisclosureGroup("Effort (optional)") {
                Toggle("Record RPE", isOn: Binding(get: { value.rpe != nil }, set: { value.rpe = $0 ? 7 : nil }))
                if value.rpe != nil {
                    Stepper("RPE: \((value.rpe ?? 7).formatted()) / 10", value: Binding(get: { value.rpe ?? 7 }, set: { value.rpe = $0 }), in: 1...10, step: 0.5)
                }
                if let target = value.targetRPE { Text("Planned effort: \(target.formatted()) / 10").foregroundStyle(FitTheme.textSecondary) }
            }.font(FitTheme.body(12))
        }
        .padding(12)
        .background(FitTheme.dashboardBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(isLogged ? FitTheme.dashboardAccent.opacity(0.3) : FitTheme.textPrimary.opacity(0.06), lineWidth: 1) }
    }
    private func previousValues(_ source: WorkoutSetReference) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.isCurrentWorkout ? "Last set · this workout" : "Last time · " + source.date.formatted(date: .abbreviated, time: .omitted))
                .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            Text(previousSummary(source.set)).font(FitTheme.medium(13)).monospacedDigit().foregroundStyle(FitTheme.dashboardAccent)
        }.fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var reuseAction: some View {
        if !isLogged && value.startedAt == nil {
            Button("Use previous", systemImage: "arrow.uturn.down", action: reuse)
                .font(FitTheme.medium(12)).frame(minHeight: 44)
                .accessibilityHint("Copies previous inputs into this set. Logging is still required.")
        }
    }
    private func previousSummary(_ set: WorkoutSet) -> String {
        switch kind {
        case .weighted: "\(unit.display(set.loadKG).formatted(.number.precision(.fractionLength(0...2)))) \(unit.rawValue) × \(set.reps) reps"
        case .bodyweight: "\(set.reps) reps"
        case .duration: WorkoutDisplay.clock(set.seconds) + (set.distanceMeters > 0 ? " · \(set.distanceMeters.formatted()) m" : "")
        }
    }
    @ViewBuilder private var timerAction: some View {
        if !isLogged {
            if value.timedActiveSeconds == nil {
                Button("Stop timer", systemImage: "stop.fill", action: stopTimer).font(FitTheme.medium(12)).frame(minHeight: 44)
            } else {
                Button("Restart", systemImage: "arrow.clockwise", action: start).font(FitTheme.medium(12)).frame(minHeight: 44).disabled(!canComplete)
            }
        }
    }
    @ViewBuilder private func setFields(stacked: Bool) -> some View {
        if kind == .duration {
            if value.startedAt != nil && value.timedActiveSeconds == nil && !isLogged {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Seconds · live").font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
                        Text(Int(session.setElapsed(value, at: context.date) ?? 0).formatted())
                            .font(FitTheme.strong(22)).monospacedDigit().frame(maxWidth: .infinity, minHeight: 60)
                            .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                    }.frame(minWidth: 84, maxWidth: .infinity)
                }
            } else { WorkoutLogNumberField(title: "Seconds", value: $value.seconds, step: 5, maximum: 86400) }
            WorkoutLogNumberField(title: "Meters (optional)", value: $value.distanceMeters, step: 50, maximum: 1_000_000)
        } else {
            if kind == .weighted {
                WorkoutLogNumberField(title: "Load · \(unit.rawValue)", value: Binding(get: { unit.display(value.loadKG) }, set: { value.loadKG = unit.kilograms($0) }), step: unit == .kg ? 2.5 : 5, maximum: unit.display(1000))
            }
            WorkoutLogNumberField(title: "Reps", value: Binding(get: { Double(value.reps) }, set: { newValue in
                if newValue.isFinite, (0...1000).contains(newValue) { value.reps = Int(newValue) }
            }), integer: true)
        }
        Button(action: complete) {
            HStack(spacing: 10) {
                Image(systemName: isLogged ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 30, weight: .regular))
                if stacked { Text(isLogged ? "Logged · Undo" : "Log set").font(FitTheme.button(14)) }
            }
                .foregroundStyle(isLogged ? FitTheme.dashboardAccent : FitTheme.textPrimary)
                .frame(minWidth: 48, minHeight: 60)
                .frame(maxWidth: stacked ? .infinity : nil)
                .background(isLogged ? FitTheme.dashboardAccent.opacity(0.1) : FitTheme.textPrimary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(RoutineEditorPressStyle()).disabled(!canComplete || (!isLogged && !canLog))
        .accessibilityLabel(isLogged ? "Set completed — undo" : "Complete set")
        .accessibilityHint(canComplete ? (isLogged ? "Undoes this set and resets its optional timer" : "Saves this set and starts its rest timer") : "Resume the workout to log sets")
        .accessibilityIdentifier("completeSet")
    }
    private func targetSummary(_ target: PlannedSet) -> String {
        if kind == .duration { return "Planned: \(target.seconds.formatted()) seconds" }
        let reps = target.repMin == target.repMax ? "\(target.repMin)" : "\(target.repMin)–\(target.repMax)"
        let load = kind == .weighted ? target.loadKG.map { " · \(unit.display($0).formatted()) \(unit.rawValue)" } ?? "" : ""
        return "Planned: \(reps) reps\(load)"
    }
}

struct WorkoutLogNumberField: View {
    let title: String
    @Binding var value: Double
    var integer = false
    var step = 1.0
    var maximum = 1000.0
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...(integer ? 0 : 2))))
                .font(FitTheme.strong(22)).monospacedDigit().multilineTextAlignment(.center)
                .keyboardType(integer ? .numberPad : .decimalPad).focused($focused)
                .padding(.horizontal, 8).frame(minHeight: 60)
                .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(focused ? FitTheme.dashboardAccent : FitTheme.subtleBorder, lineWidth: 1) }
                .accessibilityLabel(title)
            HStack(spacing: 0) {
                adjustment("minus", delta: -step)
                Spacer(minLength: 0)
                adjustment("plus", delta: step)
            }
        }.frame(minWidth: 92, maxWidth: .infinity)
    }
    private func adjustment(_ symbol: String, delta: Double) -> some View {
        Button {
            focused = false
            guard value.isFinite else { return }
            value = min(maximum, max(0, ((value + delta) * 100).rounded() / 100))
        } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).buttonRepeatBehavior(.enabled)
            .foregroundStyle(FitTheme.textSecondary)
            .disabled(!value.isFinite || (delta < 0 ? value <= 0 : value >= maximum))
            .accessibilityLabel("\(delta < 0 ? "Decrease" : "Increase") \(title) by \(step.formatted())")
    }
}

import SwiftUI

struct WorkoutLastSetActions: View {
    let store: WorkoutStore
    let sessionID: UUID
    let unit: WeightUnit
    @State private var editing: WorkoutRecordedSet?
    @State private var restarting: WorkoutRecordedSet?
    @Environment(\.fitHaptics) private var haptics
    private var last: WorkoutRecordedSet? { store.sessions.first { $0.id == sessionID }?.lastRecordedSet }
    var body: some View {
        if let last {
            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { edit(last); restart(last) }
                    VStack(spacing: 8) { edit(last); restart(last) }
                }
                Text("Last: \(last.exercise.name) · Set \(last.number)\(last.original.status == .skipped ? " · skipped" : "")")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary).lineLimit(2)
            }
            .sheet(item: $editing) { reference in
                NavigationStack { WorkoutRecordedSetEditor(store: store, reference: reference, unit: unit) }
            }
            .confirmationDialog("Restart this set?", isPresented: Binding(get: { restarting != nil }, set: { if !$0 { restarting = nil } }), titleVisibility: .visible) {
                Button("Restart set") {
                    if let restarting, store.restartRecordedSet(restarting) { haptics?.play(.selection) }
                    restarting = nil
                }
                Button("Cancel", role: .cancel) { restarting = nil }
            } message: { Text("The set's recorded result will be cleared and its timer reset. Rest ends and this set starts again. A paused workout stays paused. To correct only weights or reps, choose Edit last set.") }
        }
    }
    private func edit(_ reference: WorkoutRecordedSet) -> some View {
        Button { editing = reference } label: {
            Label("Edit last set", systemImage: "pencil").font(FitTheme.button(13)).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
                .dashboardGlass(in: Capsule(), interactive: true)
        }.buttonStyle(.fitPlain).accessibilityIdentifier("editLastRecordedSet")
            .accessibilityHint("Correct recorded values without restarting any timer.")
    }
    private func restart(_ reference: WorkoutRecordedSet) -> some View {
        Button { restarting = reference } label: {
            Label("Restart last set", systemImage: "arrow.counterclockwise").font(FitTheme.medium(13)).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10)
        }.buttonStyle(.fitPlain).disabled(store.active != nil && store.active?.id != sessionID)
            .accessibilityIdentifier("restartLastRecordedSet")
    }
}

struct WorkoutRecordedSetEditor: View {
    let store: WorkoutStore
    let reference: WorkoutRecordedSet
    let unit: WeightUnit
    @State private var value: WorkoutSet
    @State private var editing: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.fitHaptics) private var haptics
    init(store: WorkoutStore, reference: WorkoutRecordedSet, unit: WeightUnit) {
        self.store = store; self.reference = reference; self.unit = unit
        _value = State(initialValue: reference.original)
    }
    private var valid: Bool { editing.isEmpty && (try? WorkoutRecordedSetEditing.corrected(value, original: reference.original, kind: reference.exercise.kind)) != nil }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ExerciseArtwork(exercise: reference.exercise, size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(reference.exercise.name).font(FitTheme.section(19))
                        Text("Set \(reference.number) · \(reference.original.status == .completed ? "Completed" : "Skipped")").font(FitTheme.medium(13)).foregroundStyle(FitTheme.textSecondary)
                    }
                }
                Text("Correct this record. Its completion time and workout progress stay the same; no timer restarts.")
                    .font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                layout {
                    if reference.exercise.kind == .weighted {
                        WorkoutNumberWheel(title: "Weight · \(unit.rawValue)", value: Binding(get: { unit.display(value.loadKG) }, set: { value.loadKG = unit.kilograms($0) }), step: unit == .kg ? 0.5 : 1, maximum: unit.display(1000), editingChanged: { changing("weight", $0) })
                    }
                    if reference.exercise.kind != .duration {
                        WorkoutNumberWheel(title: "Recorded reps", value: Binding(get: { Double(value.reps) }, set: { value.reps = Int($0) }), integer: true,
                            minimum: reference.original.status == .completed ? 1 : 0, editingChanged: { changing("reps", $0) })
                    } else {
                        WorkoutNumberWheel(title: "Recorded seconds", value: $value.seconds, step: 1, minimum: reference.original.status == .completed ? 1 : 0, maximum: 86400, editingChanged: { changing("seconds", $0) })
                    }
                }
                if reference.exercise.kind == .duration {
                    WorkoutLogNumberField(title: "Distance · meters", value: $value.distanceMeters, step: 10, maximum: 1_000_000)
                }
                Picker("Set type", selection: $value.type) { ForEach(SetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                Toggle("Record effort (RPE)", isOn: Binding(get: { value.rpe != nil }, set: { value.rpe = $0 ? value.rpe ?? 7 : nil }))
                if value.rpe != nil {
                    Stepper("RPE · \((value.rpe ?? 7).formatted()) / 10", value: Binding(get: { value.rpe ?? 7 }, set: { value.rpe = $0 }), in: 1...10, step: 0.5)
                }
                TextField("Set note", text: Binding(get: { value.note ?? "" }, set: { value.note = $0 }), axis: .vertical)
                    .lineLimit(2...5).padding(14).fitSurface(radius: 14)
                if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red) }
                if reference.original.status == .skipped {
                    Text("This set stays skipped and contributes no training volume.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
            }.font(FitTheme.body(14)).padding(FitTheme.pageInset).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(FitTheme.dashboardBackground).foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent)
            .navigationTitle("Edit recorded set").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save changes") {
                    if store.correctRecordedSet(value, reference: reference) { haptics?.play(.saved); dismiss() }
                }.disabled(!valid).accessibilityIdentifier("saveRecordedSetCorrection") }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done typing") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
    }
    private func changing(_ id: String, _ active: Bool) { if active { editing.insert(id) } else { editing.remove(id) } }
}

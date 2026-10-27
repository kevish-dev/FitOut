import SwiftUI

struct WorkoutSessionConfigurationView: View {
    let store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    @State private var sessionID: UUID?
    @State private var destination: Destination?
    @State private var confirmation: Confirmation?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.fitHaptics) private var haptics
    private enum Destination: Identifiable {
        case edit(WorkoutEntry), replace(WorkoutEntry), add
        var id: String { switch self { case .edit(let e): "edit-\(e.id)"; case .replace(let e): "replace-\(e.id)"; case .add: "add" } }
    }
    private enum Confirmation { case focus(WorkoutEntry), skip(WorkoutEntry), remove(WorkoutEntry) }
    private var session: WorkoutSession? { store.active?.id == sessionID ? store.active : nil }
    init(store: WorkoutStore, gym: GymStore, unit: WeightUnit) {
        self.store = store; self.gym = gym; self.unit = unit
        _sessionID = State(initialValue: store.active?.id)
    }
    var body: some View {
        List {
            if let session {
                Section {
                    Text(session.title).font(FitTheme.section(20))
                    Text("Drag the handles to change the order. Choose ‘Do this next’ to switch now. Your saved weekly routine stays the same.")
                        .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                }.listRowBackground(Color.clear)
                Section {
                    ForEach(session.entries) { entry in row(entry, session: session) }
                        .onMove { offsets, target in
                            var ids = session.entries.map(\.id); ids.move(fromOffsets: offsets, toOffset: target)
                            _ = apply(.reorder(ids))
                        }
                } header: { Text("\(session.entries.count) exercises") }
                footer: { Text("Reordering preserves a running set. Replacing or removing remaining work keeps recorded sets.") }
                Section {
                    Button { destination = .add } label: { Label("Add exercises", systemImage: "plus").font(FitTheme.button(15)).frame(minHeight: 44) }
                }
            } else {
                ContentUnavailableView("Session ended", systemImage: "checkmark.circle", description: Text("Close this sheet to view the workout summary."))
            }
            if destination == nil, let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red) }
        }
        .environment(\.editMode, .constant(.active))
        .nutritionForm().navigationTitle("Session exercises").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $destination) { value in
            NavigationStack {
                switch value {
                case .add:
                    QuickWorkoutSetupView(store: store, gym: gym, unit: unit, defaults: nil, addingToSession: true, onAdded: { destination = nil })
                case .edit(let original):
                    WorkoutEntryConfigurationView(entry: original, unit: unit, reference: { entry, set in
                        WorkoutRecall.reference(for: entry, setID: set.id, current: session, history: store.history)
                    }, protectedSetID: session?.execution?.setID) { edited in
                        guard store.active?.id == sessionID else { return }
                        if store.configureExercise(edited, original: original) { destination = nil }
                    }
                    .safeAreaInset(edge: .bottom) { if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red).padding() } }
                case .replace(let original):
                    SessionReplacementPicker(store: store, gym: gym, unit: unit, entry: original, sessionID: sessionID) { destination = nil }
                }
            }
        }
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let confirmation {
                switch confirmation {
                case .focus(let e): Button("Do this next") { if apply(.focus(e.id)) { dismiss() } }
                case .skip(let e): Button("Skip remaining sets") { _ = apply(.skip(e.id)) }
                case .remove(let e): Button(e.sets.contains { $0.status != .pending } ? "Remove remaining sets" : "Remove exercise", role: .destructive) { _ = apply(.remove(e.id)) }
                }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { Text(confirmationMessage) }
    }
    private func row(_ entry: WorkoutEntry, session: WorkoutSession) -> some View {
        let remaining = entry.skipped ? 0 : entry.sets.filter { $0.status == .pending }.count
        let current = entry.id == session.execution?.entryID
        return HStack(spacing: 10) {
            ExerciseArtwork(exercise: entry.exercise, size: 46).accessibilityHidden(true)
            Button { destination = .edit(entry) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.exercise.name).font(FitTheme.section(14)).foregroundStyle(FitTheme.textPrimary)
                    Text(entry.skipped ? "Skipped" : "\(remaining) remaining · \(entry.sets.filter { $0.status == .completed }.count) logged")
                        .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                    if current { Label("Current", systemImage: "arrow.right.circle.fill").font(FitTheme.medium(11)).foregroundStyle(FitTheme.dashboardAccent) }
                }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 54)
            }.buttonStyle(.plain).accessibilityLabel("Edit \(entry.exercise.name) sets")
            Menu {
                Button("Do this next", systemImage: "play.fill") { confirmation = .focus(entry) }.disabled(remaining == 0 || current && session.execution?.phase == .activeSet)
                Button("Edit sets, weight & reps", systemImage: "slider.horizontal.3") { destination = .edit(entry) }
                Button("Replace exercise", systemImage: "arrow.triangle.2.circlepath") { destination = .replace(entry) }.disabled(remaining == 0)
                Button("Skip exercise", systemImage: "forward.end") { confirmation = .skip(entry) }.disabled(remaining == 0)
                Button(entry.sets.contains { $0.status != .pending } ? "Remove remaining sets" : "Remove exercise", systemImage: "trash", role: .destructive) { confirmation = .remove(entry) }.disabled(remaining == 0)
                Button("Move to first", systemImage: "arrow.up.to.line") {
                    let ids = [entry.id] + session.entries.filter { $0.id != entry.id }.map(\.id)
                    _ = apply(.reorder(ids))
                }.disabled(session.entries.first?.id == entry.id)
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Options for \(entry.exercise.name)")
        }.padding(.vertical, 3).listRowBackground(FitTheme.surface)
    }
    private var confirmationTitle: String {
        switch confirmation { case .focus(let e): "Switch to \(e.exercise.name)?"; case .skip(let e): "Skip \(e.exercise.name)?"; case .remove(let e): "Remove \(e.exercise.name)?"; case nil: "Update session?" }
    }
    private var confirmationMessage: String {
        switch confirmation {
        case .focus: "The current set timer will stop and rest will end. Its elapsed time and all recorded sets stay saved. Start the selected exercise when ready."
        case .skip: "Remaining sets are marked skipped and excluded from volume. Previously completed sets stay saved."
        case .remove: "Only unlogged work is removed from this session. Completed and skipped records are kept. Your saved routine stays the same."
        case nil: ""
        }
    }
    @discardableResult private func apply(_ action: WorkoutSessionEdit) -> Bool {
        guard let sessionID else { return false }
        let result = store.editSession(action, sessionID: sessionID)
        confirmation = nil
        if result { haptics?.play(.selection) }
        return result
    }
}

private struct SessionReplacementPicker: View {
    let store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    let entry: WorkoutEntry
    let sessionID: UUID?
    let close: () -> Void
    @State private var selected: ExerciseDefinition?
    var body: some View {
        ExerciseBrowser(store: gym, title: "Replace exercise", mode: .single,
            selectionHint: "Choose an alternative for \(entry.exercise.name). Recorded sets stay saved.", previousPerformance: { exercise in
                let candidate = WorkoutEntry(exercise: exercise, sets: [WorkoutSet()])
                guard let set = candidate.sets.first,
                      let source = WorkoutRecall.reference(for: candidate, setID: set.id, current: store.active, history: store.history) else { return nil }
                return WorkoutConfigurationDisplay.inputs(source.set, kind: exercise.kind, unit: unit)
            }) { exercises in
                selected = exercises.first
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) } }
            .confirmationDialog("Use \(selected?.name ?? "this exercise")?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
                Button("Replace remaining exercise") {
                    if let selected, let sessionID, store.editSession(.replace(entry.id, selected), sessionID: sessionID) { close() }
                    selected = nil
                }
            } message: { Text("Remaining sets will use this exercise's own previous performance when available. Recorded sets keep their original exercise. Replacing the current exercise ends rest and stops its set timer.") }
            .safeAreaInset(edge: .bottom) { if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.red).padding() } }
    }
}

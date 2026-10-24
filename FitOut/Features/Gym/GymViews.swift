import SwiftUI

struct MuscleSelection: View {
    @Binding var selection: [Muscle]
    @State private var showMap = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Muscle.allCases) { muscle in
                    Button {
                        if selection.contains(muscle) { selection.removeAll { $0 == muscle } }
                        else { selection.append(muscle) }
                    } label: {
                        Text(muscle.title).font(FitTheme.medium(12))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selection.contains(muscle) ? FitTheme.dashboardAccent : FitTheme.textPrimary)
                            .dashboardGlass(in: RoundedRectangle(cornerRadius: 12), highlighted: selection.contains(muscle), interactive: true)
                    }.buttonStyle(.plain).accessibilityValue(selection.contains(muscle) ? "Selected" : "Not selected")
                }
            }
            Button("Use muscle map") { showMap = true }.font(FitTheme.button(13)).frame(minHeight: 44)
        }
        .sheet(isPresented: $showMap) { NavigationStack { MuscleMapView(selection: $selection).toolbar { Button("Done") { showMap = false } } } }
    }
}

struct ExerciseLibrary: View {
    let store: GymStore
    var onSelect: ((ExerciseDefinition) -> Void)? = nil
    var body: some View {
        ExerciseBrowser(store: store, title: onSelect == nil ? "Exercise library" : "Add exercise",
                        mode: onSelect == nil ? .browse : .single,
                        onSelect: { exercises in if let first = exercises.first { onSelect?(first) } })
    }
}
struct ExerciseDetail: View {
    let store: GymStore
    let exerciseID: String
    @State private var editing: ExerciseDefinition?
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if let exercise = store.exercise(exerciseID) {
                Section {
                    ExerciseImageButton(exercise: exercise, style: .detail)
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }
                Section("Movement") {
                    Text("Primary: " + exercise.muscles.map(\.title).joined(separator: ", "))
                    if !exercise.secondary.isEmpty { Text("Secondary: " + exercise.secondary.map(\.title).joined(separator: ", ")) }
                    Text(exercise.equipment == "None" ? "No equipment" : exercise.equipment)
                    Text(exercise.pattern); Text(exercise.trackingTitle)
                }
                Section("Instructions") { Text(exercise.instructions.isEmpty ? "No instructions added." : exercise.instructions) }
                Button(exercise.isFavorite ? "Remove from favorites" : "Add to favorites") { var value = exercise; value.isFavorite.toggle(); store.saveExercise(value) }
                if exercise.isCustom {
                    Button("Edit exercise") { editing = exercise }
                    Button("Delete exercise", role: .destructive) { deleting = true }
                }
                Section("Alternatives") {
                    ForEach(store.exercises.filter { $0.id != exercise.id && $0.category == exercise.category && !Set($0.muscles).isDisjoint(with: exercise.muscles) }) { alternative in
                        NavigationLink { ExerciseDetail(store: store, exerciseID: alternative.id) } label: { ExerciseLibraryRow(exercise: alternative) }
                    }
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(store.exercise(exerciseID)?.name ?? "Exercise")
            .navigationBarTitleDisplayMode(.inline).font(FitTheme.body(14)).tint(FitTheme.dashboardAccent)
            .scrollContentBackground(.hidden).background(FitTheme.dashboardBackground)
            .sheet(item: $editing) { CustomExerciseEditor(store: store, exercise: $0) }
            .confirmationDialog("Delete custom exercise?", isPresented: $deleting) { Button("Delete", role: .destructive) { if store.deleteCustomExercise(exerciseID) { dismiss() } } }
    }
}
struct CustomExerciseEditor: View {
    let store: GymStore
    @State var exercise: ExerciseDefinition
    var onSaved: ((ExerciseDefinition) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $exercise.name).font(FitTheme.section(18)).accessibilityIdentifier("customExerciseName")
                    Picker("Track", selection: $exercise.kind) {
                        Text("Weight & reps").tag(ExerciseKind.weighted)
                        Text("Reps only").tag(ExerciseKind.bodyweight)
                        Text("Time & distance").tag(ExerciseKind.duration)
                    }
                }
                Section {
                    MuscleSelection(selection: $exercise.muscles)
                } header: { Text("Primary muscles") } footer: {
                    if exercise.muscles.isEmpty { Text("Choose at least one primary muscle to save.") }
                }
                Section {
                    DisclosureGroup("Details (optional)") {
                        TextField("Equipment", text: $exercise.equipment)
                        TextField("Other names", text: $exercise.aliases)
                        TextField("Movement pattern", text: $exercise.pattern)
                        TextField("Instructions and cues", text: $exercise.instructions, axis: .vertical)
                        DisclosureGroup("Secondary muscles") { MuscleSelection(selection: $exercise.secondary) }
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Custom exercise").navigationBarTitleDisplayMode(.inline)
                .font(FitTheme.body(14)).scrollContentBackground(.hidden).background(FitTheme.dashboardBackground)
                .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if store.saveExercise(exercise) { onSaved?(exercise); dismiss() } }
                        .disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exercise.muscles.isEmpty)
                }
            }
        }.tint(FitTheme.dashboardAccent)
    }
}

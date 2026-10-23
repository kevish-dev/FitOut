import SwiftUI

struct GymView: View {
    @Bindable var store: GymStore
    let workouts: WorkoutStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @State private var showWorkout = false
    @State private var editing: Routine?
    @State private var deleting: Routine?
    var body: some View {
        List {
            WorkoutsPanel(store: workouts, gym: store, unit: unit, defaults: defaults, showing: $showWorkout)
            NavigationLink("Exercise library") { ExerciseLibrary(store: store) }
            if store.routines.isEmpty {
                Section { ContentUnavailableView("Plan your workouts", systemImage: "calendar.badge.plus", description: Text("Choose a template or create your own weekly schedule.")) }
            }
            ForEach(store.routines) { routine in
                Section {
                    Button { editing = routine } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(routine.name, systemImage: routine.isActive ? "checkmark.circle.fill" : "calendar").font(.headline)
                            Text("\(routine.days.filter { $0.kind == .workout }.count) workout days per week").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if routine.isActive {
                        ForEach(routine.days) { day in
                            HStack { Text(RoutineSchedule.weekdays[day.weekday]); Spacer(); Text(day.kind == .workout ? day.title : day.kind.rawValue).foregroundStyle(.secondary) }
                        }
                    }
                    HStack {
                        if !routine.isActive { Button("Use routine") { var value = routine; value.isActive = true; store.save(value) } }
                        Button("Duplicate") { store.save(routine.duplicate()) }
                        Spacer()
                        Button("Delete", role: .destructive) { deleting = routine }
                    }.buttonStyle(.borderless)
                }
            }
        }.navigationTitle("Gym")
            .toolbar {
                Menu { ForEach(RoutineTemplate.allCases) { template in Button(template.rawValue) { editing = template.make() } } }
                label: { Label("New routine", systemImage: "plus") }.accessibilityIdentifier("newRoutine")
            }
            .sheet(isPresented: $showWorkout) { NavigationStack { ActiveWorkoutView(store: workouts, gym: store, unit: unit, defaults: defaults) } }
            .onChange(of: workouts.active?.id, initial: true) { _, new in if new != nil { showWorkout = true } }
            .sheet(item: $editing) { RoutineEditor(store: store, routine: $0) }
            .confirmationDialog("Delete this routine? Completed workouts will be kept.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete routine", role: .destructive) { if let deleting { store.deleteRoutine(deleting.id) }; deleting = nil }
            }
            .alert("Could not save", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
    }
}

struct RoutineEditor: View {
    let store: GymStore
    @State var routine: Routine
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Routine name", text: $routine.name).accessibilityIdentifier("routineName")
                    Toggle("Active routine", isOn: $routine.isActive)
                }
                Section("Weekly schedule") {
                    ForEach($routine.days) { $day in
                        NavigationLink { RoutineDayEditor(store: store, day: $day) } label: {
                            LabeledContent(RoutineSchedule.weekdays[day.weekday], value: day.kind == .workout ? day.title : day.kind.rawValue)
                        }
                    }
                }
                Section("Move a day") {
                    Text("Moving swaps the two days and preserves both workouts.").font(.caption)
                    ForEach(routine.days) { day in
                        Picker(day.title.isEmpty ? RoutineSchedule.weekdays[day.weekday] : day.title, selection: Binding(get: { day.weekday }, set: { RoutineSchedule.move(dayID: day.id, to: $0, in: &routine) })) {
                            ForEach(0..<7, id: \.self) { Text(RoutineSchedule.weekdays[$0]).tag($0) }
                        }
                    }
                }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Edit routine")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.save(routine) { dismiss() } }.accessibilityIdentifier("saveRoutine") }
                }
        }
    }
}

struct RoutineDayEditor: View {
    let store: GymStore
    @Binding var day: RoutineDay
    @State private var picking = false
    var body: some View {
        Form {
            Picker("Day type", selection: $day.kind) { ForEach(RoutineDayKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            if day.kind == .workout {
                TextField("Workout title", text: $day.title)
                Toggle("Duration target", isOn: Binding(get: { day.durationMinutes != nil }, set: { day.durationMinutes = $0 ? 45 : nil }))
                if day.durationMinutes != nil { Stepper("\(day.durationMinutes ?? 45) minutes", value: Binding(get: { day.durationMinutes ?? 45 }, set: { day.durationMinutes = $0 }), in: 1...600, step: 5) }
                Section("Focus muscles") { MuscleSelection(selection: $day.muscles) }
                Section("Exercises") {
                    ForEach($day.exercises) { $plan in
                        NavigationLink { PlannedExerciseEditor(store: store, plan: $plan) } label: {
                            VStack(alignment: .leading) {
                                Text(store.exercise(plan.exerciseID)?.name ?? "Unavailable exercise")
                                Text("\(plan.sets) sets · \(plan.repMin)–\(plan.repMax) reps · \(plan.restSeconds)s rest").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.onDelete { day.exercises.remove(atOffsets: $0) }.onMove { day.exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add exercise") { picking = true }
                }
            } else { Text("Exercises stay saved if you temporarily change this day to rest or flexible.").font(.caption) }
        }.navigationTitle(RoutineSchedule.weekdays[day.weekday]).toolbar { EditButton() }
            .sheet(isPresented: $picking) { NavigationStack { ExerciseLibrary(store: store) { exercise in day.exercises.append(PlannedExercise(exerciseID: exercise.id)); picking = false } } }
    }
}
struct PlannedExerciseEditor: View {
    let store: GymStore
    @Binding var plan: PlannedExercise
    @State private var replacing = false
    var body: some View {
        Form {
            Button("Replace exercise") { replacing = true }
            Stepper("Working sets: \(plan.sets)", value: $plan.sets, in: 1...30)
            Stepper("Warm-up sets: \(plan.warmupSets)", value: $plan.warmupSets, in: 0...10)
            Stepper("Minimum reps: \(plan.repMin)", value: $plan.repMin, in: 1...100).onChange(of: plan.repMin) { _, value in plan.repMax = max(value, plan.repMax) }
            Stepper("Maximum reps: \(plan.repMax)", value: $plan.repMax, in: plan.repMin...100)
            Stepper("Rest: \(plan.restSeconds)s", value: $plan.restSeconds, in: 0...3600, step: 15)
            Toggle("Target load", isOn: Binding(get: { plan.loadKG != nil }, set: { plan.loadKG = $0 ? 0 : nil }))
            if plan.loadKG != nil { LabeledContent("Load (kg)") { TextField("kg", value: Binding(get: { plan.loadKG ?? 0 }, set: { plan.loadKG = $0 }), format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
            TextField("Notes", text: $plan.notes, axis: .vertical)
        }.navigationTitle(store.exercise(plan.exerciseID)?.name ?? "Exercise")
            .sheet(isPresented: $replacing) { NavigationStack { ExerciseLibrary(store: store) { plan.exerciseID = $0.id; replacing = false } } }
    }
}
struct MuscleSelection: View {
    @Binding var selection: [Muscle]
    @State private var showMap = false
    var body: some View {
        Button("Select on muscle map") { showMap = true }
        ForEach(Muscle.allCases) { muscle in
            Toggle(muscle.title, isOn: Binding(get: { selection.contains(muscle) }, set: { enabled in if enabled { if !selection.contains(muscle) { selection.append(muscle) } } else { selection.removeAll { $0 == muscle } } }))
        }
        .sheet(isPresented: $showMap) { NavigationStack { MuscleMapView(selection: $selection).toolbar { Button("Done") { showMap = false } } } }
    }
}

struct ExerciseLibrary: View {
    @Bindable var store: GymStore
    var onSelect: ((ExerciseDefinition) -> Void)? = nil
    @State private var search = ""
    @State private var muscles: [Muscle] = []
    @State private var favorites = false
    @State private var showMap = false
    @State private var custom: ExerciseDefinition?
    @Environment(\.dismiss) private var dismiss
    private var filtered: [ExerciseDefinition] {
        store.exercises.filter { (!favorites || $0.isFavorite) && (search.isEmpty || ($0.name + " " + $0.aliases + " " + $0.equipment).localizedCaseInsensitiveContains(search)) && (muscles.isEmpty || !Set($0.muscles).isDisjoint(with: muscles)) }
    }
    var body: some View {
        List {
            Toggle("Favorites only", isOn: $favorites)
            Button(muscles.isEmpty ? "Filter by muscle" : "Muscles: \(muscles.map(\.title).joined(separator: ", "))") { showMap = true }
            if !muscles.isEmpty { Button("Clear muscle filter") { muscles = [] } }
            if filtered.isEmpty { Text("No matching exercises. Adjust filters or create your own.").foregroundStyle(.secondary) }
            ForEach(filtered) { exercise in
                if let onSelect { Button(exercise.name) { onSelect(exercise) } }
                else { NavigationLink { ExerciseDetail(store: store, exerciseID: exercise.id) } label: { Label(exercise.name, systemImage: exercise.isFavorite ? "star.fill" : "dumbbell") } }
            }
        }.navigationTitle("Exercise library").searchable(text: $search)
            .toolbar {
                Button("Custom exercise", systemImage: "plus") { custom = ExerciseDefinition(name: "", muscles: [], isCustom: true) }
                if onSelect != nil { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showMap) { NavigationStack { MuscleMapView(selection: $muscles).toolbar { Button("Done") { showMap = false } } } }
            .sheet(item: $custom) { CustomExerciseEditor(store: store, exercise: $0) }
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
                Section("Movement") {
                    Text(exercise.muscles.map(\.title).joined(separator: ", "))
                    if !exercise.secondary.isEmpty { Text("Secondary: " + exercise.secondary.map(\.title).joined(separator: ", ")) }
                    Text(exercise.equipment); Text(exercise.pattern); Text(exercise.kind.rawValue.capitalized)
                }
                Section("Instructions") { Text(exercise.instructions.isEmpty ? "No instructions added." : exercise.instructions) }
                Button(exercise.isFavorite ? "Remove from favorites" : "Add to favorites") { var value = exercise; value.isFavorite.toggle(); store.saveExercise(value) }
                if exercise.isCustom {
                    Button("Edit exercise") { editing = exercise }
                    Button("Delete exercise", role: .destructive) { deleting = true }
                }
                Section("Alternatives") {
                    ForEach(store.exercises.filter { $0.id != exercise.id && !Set($0.muscles).isDisjoint(with: exercise.muscles) }) { Text($0.name) }
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(store.exercise(exerciseID)?.name ?? "Exercise")
            .sheet(item: $editing) { CustomExerciseEditor(store: store, exercise: $0) }
            .confirmationDialog("Delete custom exercise?", isPresented: $deleting) { Button("Delete", role: .destructive) { if store.deleteCustomExercise(exerciseID) { dismiss() } } }
    }
}
struct CustomExerciseEditor: View {
    let store: GymStore
    @State var exercise: ExerciseDefinition
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $exercise.name)
                TextField("Aliases", text: $exercise.aliases)
                TextField("Equipment", text: $exercise.equipment)
                TextField("Movement pattern", text: $exercise.pattern)
                Picker("Tracking", selection: $exercise.kind) { ForEach(ExerciseKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                TextField("Instructions and cues", text: $exercise.instructions, axis: .vertical)
                Section("Primary muscles") { MuscleSelection(selection: $exercise.muscles) }
                Section("Secondary muscles") { MuscleSelection(selection: $exercise.secondary) }
                if let error = store.error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Custom exercise").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.saveExercise(exercise) { dismiss() } } }
            }
        }
    }
}

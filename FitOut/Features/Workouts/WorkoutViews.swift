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
                Text("\(active.completedSets.count) sets saved · \(active.status == .paused ? "Paused" : "In progress")").font(.caption)
            } else {
                Button("Start quick workout") { if store.start(catalogue: gym.exercises) { showing = true } }.accessibilityIdentifier("startQuickWorkout")
                if let routine = gym.activeRoutine, let day = RoutineSchedule.day(in: routine, at: .now), day.kind == .workout {
                    Button("Start \(day.title)") { if store.start(day: day, routineID: routine.id, catalogue: gym.exercises) { showing = true } }
                }
            }
            NavigationLink("Workout history") { WorkoutHistory(store: store, unit: unit) }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }

    }
}
struct ActiveWorkoutView: View {
    @Bindable var store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    let defaults: UserDefaults
    @State private var now = Date()
    @State private var selecting = false
    @State private var replacing: UUID?
    @State private var finishing = false
    @State private var finished: WorkoutSession?
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        Group {
            if let session = store.active {
                List {
                    Section {
                        Text(session.title).font(.title2.bold())
                        Text("\(Int(session.duration(at: now) / 60)) min · \(session.completedSets.count) completed sets")
                        Button(session.status == .paused ? "Resume" : "Pause") { if session.status == .paused { store.resume() } else { store.pause() } }
                        if let deadline = session.restUntil {
                            Text("Rest: \(max(0, Int(ceil(deadline.timeIntervalSince(now))))) seconds").monospacedDigit()
                            Button("End rest") { store.update { $0.restUntil = nil } }
                        }
                        TextField("Workout notes", text: Binding(get: { store.active?.notes ?? "" }, set: { value in store.update { $0.notes = value } }), axis: .vertical)
                    }
                    ForEach(session.entries) { entry in
                        Section(entry.exercise.name + (entry.skipped ? " · Skipped" : "")) {
                            if !entry.skipped {
                                ForEach(entry.sets) { set in
                                    WorkoutSetEditor(value: setBinding(entry.id, set.id), kind: entry.exercise.kind, unit: unit) { store.toggleSet(entryID: entry.id, setID: set.id) }
                                        .swipeActions { Button("Delete", role: .destructive) { changeEntry(entry.id) { $0.sets.removeAll { $0.id == set.id } } } }
                                }
                                Button("Add set") { changeEntry(entry.id) { $0.sets.append(WorkoutSet()) } }
                            }
                            TextField("Exercise notes", text: Binding(get: { store.active?.entries.first { $0.id == entry.id }?.notes ?? "" }, set: { value in changeEntry(entry.id) { $0.notes = value } }), axis: .vertical)
                            HStack {
                                Button(entry.skipped ? "Restore exercise" : "Skip exercise") { changeEntry(entry.id) { $0.skipped.toggle() } }
                                Spacer()
                                Button("Replace") { replacing = entry.id; selecting = true }
                            }.buttonStyle(.borderless)
                        }
                    }
                    Button("Add exercise") { replacing = nil; selecting = true }.accessibilityIdentifier("workoutAddExercise")
                    Button("Finish workout") { finishing = true }.accessibilityIdentifier("finishWorkout")
                }
            } else if let finished { WorkoutSummary(session: finished, unit: unit) }
            else { ContentUnavailableView("No active workout", systemImage: "dumbbell", description: Text("Your ended sessions are in workout history.")) }
        }.navigationTitle(finished == nil ? "Workout" : "Workout summary")
            .toolbar { Button("Close") { dismiss() } }
            .sheet(isPresented: $selecting) { NavigationStack { ExerciseLibrary(store: gym) { exercise in if let replacing { store.replace(entryID: replacing, with: exercise) } else { store.add(exercise) }; selecting = false } } }
            .confirmationDialog("End this workout", isPresented: $finishing) {
                Button("Complete workout") { finish(.completed) }
                Button("Mark skipped") { finish(.skipped) }
                Button("Abandon workout", role: .destructive) { finish(.abandoned) }
            }
            .alert("Workout could not be updated", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
            .onReceive(timer) { date in
                now = date
                if let deadline = store.active?.restUntil, deadline <= date {
                    if store.update({ $0.restUntil = nil }), !defaults.bool(forKey: "haptics.disabled") { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            }
    }
    private func finish(_ status: SessionStatus) { let id = store.active?.id; if store.finish(status) { finished = store.history.first { $0.id == id } } }
    private func changeEntry(_ id: UUID, _ mutation: (inout WorkoutEntry) -> Void) { store.update { s in if let i = s.entries.firstIndex(where: { $0.id == id }) { mutation(&s.entries[i]) } } }
    private func setBinding(_ entry: UUID, _ set: UUID) -> Binding<WorkoutSet> {
        Binding(get: { store.active?.entries.first { $0.id == entry }?.sets.first { $0.id == set } ?? WorkoutSet() }, set: { value in changeEntry(entry) { e in if let i = e.sets.firstIndex(where: { $0.id == set }) { e.sets[i] = value } } })
    }
}
struct WorkoutSetEditor: View {
    @Binding var value: WorkoutSet
    let kind: ExerciseKind
    let unit: WeightUnit
    let complete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Set type", selection: $value.type) { ForEach(SetType.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            if kind == .duration {
                number("Seconds", binding: $value.seconds)
                number("Distance (m, optional)", binding: $value.distanceMeters)
            } else {
                Stepper("Reps: \(value.reps)", value: $value.reps, in: 0...1000)
                if kind == .weighted { number("Load (\(unit.rawValue))", binding: Binding(get: { unit.display(value.loadKG) }, set: { value.loadKG = unit.kilograms($0) })) }
            }
            Toggle("Record RPE", isOn: Binding(get: { value.rpe != nil }, set: { value.rpe = $0 ? 7 : nil }))
            if value.rpe != nil { Stepper("RPE: \((value.rpe ?? 7).formatted())", value: Binding(get: { value.rpe ?? 7 }, set: { value.rpe = $0 }), in: 1...10, step: 0.5) }
            Button(action: complete) { Label(value.completedAt == nil ? "Complete set" : "Set completed — undo", systemImage: value.completedAt == nil ? "circle" : "checkmark.circle.fill") }.buttonStyle(.borderedProminent).accessibilityIdentifier("completeSet")
        }
    }
    private func number(_ title: String, binding: Binding<Double>) -> some View {
        LabeledContent(title) { TextField(title, value: binding, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
    }
}
struct WorkoutSummary: View {
    let session: WorkoutSession
    let unit: WeightUnit
    var body: some View {
        List {
            Section(session.title) {
                Text(session.status.rawValue.capitalized)
                Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                Text("\(session.completedExercises) exercises · \(session.completedSets.count) sets · \(Int(session.duration() / 60)) min")
                Text("Weighted volume: \(unit.display(session.volumeKG).formatted()) \(unit.rawValue)·reps")
                Text("Working and drop sets only. Bodyweight and duration work are recorded separately.").font(.caption).foregroundStyle(.secondary)
                if !session.notes.isEmpty { Text(session.notes) }
            }
            ForEach(session.entries) { entry in
                Section(entry.exercise.name) {
                    if entry.skipped { Text("Exercise skipped") }
                    ForEach(entry.sets) { set in
                        if set.completedAt != nil {
                            if entry.exercise.kind == .duration { Text("\(set.seconds.formatted()) sec · \(set.distanceMeters.formatted()) m") }
                            else { Text("\(set.type.rawValue): \(set.reps) reps" + (entry.exercise.kind == .weighted ? " × \(unit.display(set.loadKG).formatted()) \(unit.rawValue)" : " · bodyweight")) }
                        }
                    }
                    if !entry.notes.isEmpty { Text(entry.notes) }
                }
            }
        }.navigationTitle("Workout summary")
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
                NavigationLink { WorkoutSummary(session: session, unit: unit) } label: {
                    VStack(alignment: .leading) { Text(session.title); Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.status.rawValue)").font(.caption).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete", role: .destructive) { deleting = session.id } }
            }
        }.navigationTitle("Workout history")
            .confirmationDialog("Delete this workout and its sets?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Delete", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil } }
    }
}

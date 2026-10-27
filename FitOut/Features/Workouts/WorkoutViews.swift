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
                Text("\(active.completedSets.count) sets saved · \(active.status == .paused ? "Paused" : "In progress")").font(FitTheme.body(12))
            } else {
                Button("Configure quick workout") { showing = true }.accessibilityIdentifier("startQuickWorkout")
                if let routine = gym.activeRoutine, let day = RoutineSchedule.day(in: routine, at: .now), day.kind == .workout {
                    Button("Start \(day.title)") { if store.start(day: day, routineID: routine.id, catalogue: gym.exercises) { showing = true } }
                }
            }
            NavigationLink("Workout history") { WorkoutHistory(store: store, unit: unit) }
            NavigationLink("Analytics and calendar") { AnalyticsView(store: store, gym: gym, unit: unit) }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }

    }
}
struct WorkoutSummary: View {
    private let snapshot: WorkoutSession
    let unit: WeightUnit
    var history: [WorkoutSession] = []
    var store: WorkoutStore? = nil
    var showsLastSetActions = true
    @State private var showTiming = false
    @State private var editing: WorkoutRecordedSet?
    private var session: WorkoutSession { store?.sessions.first { $0.id == snapshot.id } ?? snapshot }
    private var records: [String] { Array(Set(WorkoutAnalytics.newRecords(in: session, history: store?.history ?? history))).sorted() }
    init(session: WorkoutSession, unit: WeightUnit, history: [WorkoutSession] = [], store: WorkoutStore? = nil, showsLastSetActions: Bool = true) {
        snapshot = session; self.unit = unit; self.history = history; self.store = store; self.showsLastSetActions = showsLastSetActions
    }
    var body: some View {
        let unit = session.execution?.preferredUnit ?? self.unit
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                WorkoutSessionHero(session: session, unit: unit, now: session.endedAt ?? .now)
                Label("\(session.completedSets.count) completed · \(session.skippedSets.count) skipped · \(session.remainingSetCount) unfinished", systemImage: "checklist")
                    .font(FitTheme.medium(13))
                if let store, showsLastSetActions {
                    WorkoutLastSetActions(store: store, sessionID: session.id, unit: unit)
                    if let error = store.error { Text(error).font(FitTheme.body(12)).foregroundStyle(.red) }
                }
                Label(session.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                Button("Timing & session timeline", systemImage: "stopwatch") { showTiming = true }
                    .font(FitTheme.button(14)).frame(minHeight: 44)
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("New personal records", systemImage: "trophy").font(FitTheme.section(17)).foregroundStyle(FitTheme.dashboardAccent)
                        ForEach(records, id: \.self) { Text($0).font(FitTheme.body(14)) }
                    }.routinePanel()
                }
                if !session.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Session notes", systemImage: "note.text").font(FitTheme.section(15))
                        Text(session.notes).font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
                    }.routinePanel()
                }
                ForEach(session.entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ExerciseImageButton(exercise: entry.exercise, style: .thumbnail(60))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.exercise.name).font(FitTheme.section(16))
                                Text(entry.skipped ? "Skipped" : "\(entry.sets.filter { $0.completedAt != nil }.count) sets logged")
                                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }
                        }
                        let completed = entry.sets.filter { $0.status != .pending }
                        if !completed.isEmpty { Divider().overlay(FitTheme.textPrimary.opacity(0.06)) }
                        ForEach(completed) { set in
                            if store != nil, let reference = session.recordedSet(entryID: entry.id, setID: set.id) {
                                HStack {
                                    Text("Set \(reference.number)").font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
                                    Spacer()
                                    Button { editing = reference } label: { Label("Edit", systemImage: "pencil").font(FitTheme.medium(12)).frame(minHeight: 44) }
                                        .buttonStyle(.plain).accessibilityLabel("Edit \(entry.exercise.name), set \(reference.number)")
                                }
                            }
                            if set.status == .skipped {
                                Label("Set \((entry.sets.firstIndex { $0.id == set.id } ?? 0) + 1) · Skipped", systemImage: "forward.end")
                                    .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                                if let elapsed = set.timedActiveSeconds { Text("Time before skip · " + WorkoutDisplay.clock(elapsed)).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
                            } else {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(FitTheme.dashboardAccent).font(.system(size: 13))
                                VStack(alignment: .leading, spacing: 4) {
                                    if set.type != .working { Text(set.type.rawValue).font(FitTheme.medium(10)).foregroundStyle(FitTheme.textSecondary) }
                                    Text(entry.exercise.kind == .duration ? "\(set.seconds.formatted()) sec" : "\(set.reps) reps").font(FitTheme.strong(15))
                                    if let elapsed = set.actual?.seconds { Text("Set duration · " + WorkoutDisplay.clock(elapsed)).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
                                }
                                Spacer(minLength: 4)
                                if entry.exercise.kind == .weighted {
                                    Text("\(unit.display(set.loadKG).formatted()) \(unit.rawValue)").font(FitTheme.body(14)).monospacedDigit()
                                } else if entry.exercise.kind == .duration && set.distanceMeters > 0 {
                                    Text("\(set.distanceMeters.formatted()) m").font(FitTheme.body(14))
                                }
                            }
                            }
                            if let note = set.note, !note.isEmpty { Text(note).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary) }
                        }
                        if completed.isEmpty && !entry.skipped { Text("No sets logged").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary) }
                        if !entry.notes.isEmpty { Text(entry.notes).font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary) }
                    }
                    .padding(FitTheme.cardInset).frame(maxWidth: .infinity, alignment: .leading)
                    .dashboardGlass(in: RoundedRectangle(cornerRadius: 22))
                }
                if session.entries.contains(where: { $0.exercise.kind == .weighted }) {
                    Text("Volume includes logged working and drop sets. Warm-ups are kept in the session but excluded from volume.")
                        .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }
            }
            .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
        }
        .background(FitTheme.dashboardBackground).foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent)
        .navigationTitle("Workout summary").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTiming) { WorkoutTimingDetails(session: session, unit: unit) }
        .sheet(item: $editing) { reference in
            if let store { NavigationStack { WorkoutRecordedSetEditor(store: store, reference: reference, unit: unit) } }
        }
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
                NavigationLink { WorkoutSummary(session: session, unit: unit, history: store.history, store: store) } label: {
                    VStack(alignment: .leading) { Text(session.title); Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(session.status.rawValue)").font(FitTheme.body(12)).foregroundStyle(.secondary) }
                }.swipeActions { Button("Delete", role: .destructive) { deleting = session.id } }
            }
        }.navigationTitle("Workout history")
            .confirmationDialog("Delete this workout and its sets?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Delete", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil } }
    }
}

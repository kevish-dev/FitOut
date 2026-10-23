import SwiftUI
import Charts

struct AnalyticsView: View {
    let store: WorkoutStore
    let gym: GymStore
    let unit: WeightUnit
    @State private var since = Calendar.current.date(byAdding: .month, value: -3, to: .now)!
    @State private var until = Date()
    @State private var exerciseID = ""
    @State private var month = Date()
    @State private var exportURL: URL?
    @State private var error: String?
    private var filtered: [WorkoutSession] { store.history.filter { $0.startedAt >= Calendar.current.startOfDay(for: since) && $0.startedAt < Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: until))! && (exerciseID.isEmpty || $0.entries.contains { $0.exercise.id == exerciseID }) } }
    private var completed: [WorkoutSession] { filtered.filter { $0.status == .completed } }
    private var historyExercises: [ExerciseDefinition] { var seen = Set<String>(); return store.history.flatMap(\.entries).map(\.exercise).filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name } }
    var body: some View {
        List {
            Section("Filters") {
                DatePicker("From", selection: $since, in: ...until, displayedComponents: .date)
                DatePicker("Through", selection: $until, in: since..., displayedComponents: .date)
                Picker("Exercise", selection: $exerciseID) { Text("All exercises").tag(""); ForEach(historyExercises) { Text($0.name).tag($0.id) } }
            }
            Section("Consistency") {
                Text("\(WorkoutAnalytics.weeklyStreak(store.history)) week streak").font(.headline)
                Text("At least one completed workout per calendar week. The current week has until its end to continue a streak; rest days do not break it.").font(.caption)
                Text("\(completed.count) completed · \(filtered.filter { $0.status == .skipped }.count) skipped")
                if let routine = gym.activeRoutine { Text("Current weekly plan: \(routine.days.filter { $0.kind == .workout }.count) sessions. Plans reflect your current schedule, not historical adherence.").font(.caption) }
            }
            calendarSection
            if completed.isEmpty { ContentUnavailableView("Your trends will appear as you log", systemImage: "chart.xyaxis.line", description: Text("No completed workouts match these filters.")) }
            else {
                Section("Weekly weighted volume") {
                    let points = WorkoutAnalytics.weeklyVolumes(completed)
                    Chart(points) { BarMark(x: .value("Week", $0.date, unit: .weekOfYear), y: .value("\(unit.rawValue)·reps", unit.display($0.value))) }.frame(height: 180)
                    Text("Total: \(unit.display(completed.reduce(0) { $0 + $1.volumeKG }).formatted()) \(unit.rawValue)·reps")
                }
                if !exerciseID.isEmpty { strengthSection }
                Section("Primary muscle volume") {
                    Text("Each set’s volume is split equally across its primary muscles.").font(.caption)
                    ForEach(Muscle.allCases) { muscle in
                        if let volume = WorkoutAnalytics.muscleVolume(completed)[muscle], volume > 0 {
                            LabeledContent(muscle.title, value: "\(unit.display(volume).formatted()) \(unit.rawValue)·reps")
                            Text("\(completed.filter { $0.entries.contains { $0.exercise.muscles.contains(muscle) && $0.sets.contains { $0.completedAt != nil } } }.count) sessions").font(.caption)
                        }
                    }
                }
            }
            Section("Matching workouts") { ForEach(filtered) { session in NavigationLink(session.title + " · " + session.startedAt.formatted(date: .abbreviated, time: .omitted)) { WorkoutSummary(session: session, unit: unit, history: store.history) } } }
            Section("Export filtered history") {
                Button("Prepare JSON export") { export(json: true) }
                Button("Prepare CSV export") { export(json: false) }
                if let exportURL { ShareLink("Share export", item: exportURL) }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }.navigationTitle("Analytics")
    }
    private var strengthSection: some View {
        Section("Personal records") {
            let record = WorkoutAnalytics.records(exerciseID: exerciseID, sessions: completed)
            if let max = record.maxLoadKG { LabeledContent("Max load", value: "\(unit.display(max).formatted()) \(unit.rawValue)") }
            if let estimate = record.estimated1RM { LabeledContent("Estimated 1RM", value: "\(unit.display(estimate).formatted()) \(unit.rawValue)") }
            Text("Epley estimate for 2–10 reps; one rep uses actual load. Working/drop weighted sets only. Estimates are not prescribed loads.").font(.caption)
            ForEach(record.repsAtLoad.keys.sorted(), id: \.self) { load in Text("\(record.repsAtLoad[load] ?? 0) reps at \(unit.display(load).formatted()) \(unit.rawValue)") }
            let points = completed.sorted { $0.startedAt < $1.startedAt }.compactMap { s -> AnalyticsPoint? in guard let value = WorkoutAnalytics.records(exerciseID: exerciseID, sessions: [s]).estimated1RM else { return nil }; return AnalyticsPoint(date: s.startedAt, value: value) }
            if points.count >= 2 { Chart(points) { LineMark(x: .value("Date", $0.date), y: .value("Estimated 1RM", unit.display($0.value))); PointMark(x: .value("Date", $0.date), y: .value("Estimated 1RM", unit.display($0.value))) }.frame(height: 180) }
        }
    }
    private var calendarSection: some View {
        Section("Calendar and activity") {
            DatePicker("Month", selection: $month, displayedComponents: .date)
            let calendar = Calendar.current
            let start = calendar.dateInterval(of: .month, for: month)!.start
            let count = calendar.range(of: .day, in: .month, for: month)!.count
            let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 35) }
                ForEach(0..<count, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index, to: start)!
                    let label = WorkoutAnalytics.dayLabel(date, sessions: store.sessions, routine: gym.activeRoutine)
                    VStack { Text("\(index + 1)"); Text(String(label.prefix(1))).font(.caption2) }
                        .frame(maxWidth: .infinity).padding(.vertical, 5).background(label == "Completed" ? FitTheme.orange.opacity(0.45) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                        .accessibilityElement(children: .ignore).accessibilityLabel(date.formatted(date: .complete, time: .omitted) + ", " + label)
                }
            }
            Text("C completed · S skipped · A abandoned · R rest · P planned · F flexible · I in progress · N no log").font(.caption)
        }
    }
    private func export(json: Bool) {
        do {
            let data: Data
            if json { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; data = try encoder.encode(filtered) }
            else { data = Data(WorkoutAnalytics.csv(filtered).utf8) }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FitOut-workouts-\(UUID().uuidString)." + (json ? "json" : "csv"))
            try data.write(to: url, options: [.atomic, .completeFileProtection]); exportURL = url; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

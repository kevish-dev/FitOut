import SwiftUI

struct WorkoutTimingDetails: View {
    let session: WorkoutSession
    let unit: WeightUnit
    @State private var showTimeline = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(session.title).font(FitTheme.section(19))
                            LabeledContent("Active", value: preciseTime(session.duration(at: context.date)))
                            LabeledContent("Paused", value: preciseTime(session.totalPaused(at: context.date)))
                            LabeledContent("Total elapsed", value: preciseTime(max(0, (session.endedAt ?? context.date).timeIntervalSince(session.startedAt))))
                        }.font(FitTheme.medium(14)).monospacedDigit().routinePanel()
                    }
                    Picker("Timing detail", selection: $showTimeline) {
                        Text("Laps (\(session.telemetry?.laps.count ?? 0))").tag(false)
                        Text("Timeline").tag(true)
                    }.pickerStyle(.segmented)
                    if let log = session.telemetry {
                        if log.recordedSince.timeIntervalSince(session.startedAt) > 1 {
                            Text("Detailed events recorded from \(log.recordedSince.formatted(date: .abbreviated, time: .standard)). Earlier totals are preserved.")
                                .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                        }
                        if showTimeline {
                            ForEach(log.events.sorted { $0.date > $1.date }) { event in eventRow(event) }
                        } else {
                            if log.laps.isEmpty {
                                ContentUnavailableView("No laps yet", systemImage: "flag", description: Text("Use Record lap during the workout to save an active-time split."))
                            }
                            ForEach(log.laps.reversed()) { lap in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label("Lap \(lap.number)", systemImage: "flag.fill").font(FitTheme.section(15))
                                        Spacer()
                                        Text(preciseTime(lap.activeSeconds)).font(FitTheme.metric(18)).monospacedDigit()
                                    }
                                    Text("\(lap.endedAt.formatted(date: .omitted, time: .standard)) · \(preciseTime(max(0, lap.wallSeconds - lap.activeSeconds))) paused in this split")
                                        .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                                    Text("Total active: \(preciseTime(lap.elapsedActiveSeconds))").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                                }.routinePanel()
                            }
                        }
                    } else {
                        Text("Detailed events were not recorded for this older session.").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                    }
                    DisclosureGroup("Pause history") {
                        ForEach(session.telemetry?.pauses ?? []) { pause in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pause.startedAt, format: .dateTime.hour().minute().second())
                                Text(pause.endedAt.map { preciseTime(max(0, $0.timeIntervalSince(pause.startedAt))) } ?? "Currently paused")
                                    .foregroundStyle(FitTheme.textSecondary)
                            }.padding(.vertical, 6)
                        }
                    }.font(FitTheme.body(13)).routinePanel()
                    Button("Prepare full session export", systemImage: "square.and.arrow.up") { export() }
                        .font(FitTheme.button(14)).frame(minHeight: 44)
                    if let exportURL { ShareLink("Share session JSON", item: exportURL).frame(minHeight: 44) }
                    if let exportError { Text(exportError).font(FitTheme.body(12)).foregroundStyle(.orange) }
                }
                .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
            }
            .background(FitTheme.dashboardBackground)
            .navigationTitle("Timing & laps").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.foregroundStyle(.white).tint(FitTheme.dashboardAccent).preferredColorScheme(.dark)
    }
    private func eventRow(_ event: WorkoutEvent) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active time: \(preciseTime(event.activeSeconds))").font(FitTheme.medium(12))
                if let before = event.beforeSet { Text("Before: " + describe(before, at: event.activeSeconds)).font(FitTheme.body(12)) }
                if let after = event.afterSet { Text("After: " + describe(after, at: event.activeSeconds)).font(FitTheme.body(12)) }
                if let text = event.beforeText, !text.isEmpty { Text("Before: " + text).font(FitTheme.body(12)) }
                if let text = event.afterText, !text.isEmpty { Text(text).font(FitTheme.body(12)) }
                if let deadline = event.beforeDeadline { Text("Previous rest deadline: " + deadline.formatted(date: .omitted, time: .standard)).font(FitTheme.body(12)) }
                if let deadline = event.afterDeadline { Text("Rest deadline: " + deadline.formatted(date: .omitted, time: .standard)).font(FitTheme.body(12)) }
                Text(event.origin == .liveActivity ? "Action from Live Activity" : "Action in FitOut")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }.padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.kind.title).font(FitTheme.section(14))
                if let exercise = event.exerciseName { Text(exercise).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary) }
                Text(event.date, format: .dateTime.hour().minute().second()).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
        }.routinePanel()
    }
    private func describe(_ set: WorkoutSet, at activeSeconds: TimeInterval) -> String {
        var parts = [set.type.rawValue, "\(set.reps) reps", "\(unit.display(set.loadKG).formatted()) \(unit.rawValue)"]
        if set.seconds > 0 { parts.append("\(set.seconds.formatted()) sec") }
        if set.distanceMeters > 0 { parts.append("\(set.distanceMeters.formatted()) m") }
        if let rpe = set.rpe { parts.append("RPE \(rpe.formatted())") }
        if let start = set.startedActiveSeconds {
            let elapsed = set.timedActiveSeconds ?? max(0, (set.loggedActiveSeconds ?? activeSeconds) - start)
            parts.append("Timer \(preciseTime(elapsed))")
        }
        return parts.joined(separator: " · ")
    }
    private func export() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("FitOut-session-\(session.id).json")
            try encoder.encode(session).write(to: url, options: [.atomic, .completeFileProtection])
            exportURL = url; exportError = nil
        } catch { exportError = error.localizedDescription }
    }
}

private func preciseTime(_ seconds: TimeInterval) -> String {
    let ticks = Int((max(0, seconds) * 100).rounded())
    return ticks >= 360_000
        ? String(format: "%d:%02d:%05.2f", ticks / 360_000, ticks / 6000 % 60, Double(ticks % 6000) / 100)
        : String(format: "%02d:%05.2f", ticks / 6000, Double(ticks % 6000) / 100)
}

struct WorkoutSetClock: View {
    let session: WorkoutSession
    let set: WorkoutSet
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Label("Set timer · " + WorkoutDisplay.clock(session.setElapsed(set, at: context.date) ?? 0), systemImage: "stopwatch")
                .font(FitTheme.medium(13)).monospacedDigit().foregroundStyle(FitTheme.dashboardAccent)
        }
    }
}

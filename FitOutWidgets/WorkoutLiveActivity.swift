import SwiftUI
import WidgetKit
import ActivityKit

struct FitOutWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveAttributes.self) { context in
            WorkoutLiveLockScreen(context: context)
                .activityBackgroundTint(Color(red: 0.045, green: 0.045, blue: 0.055))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "fitout://widget/workout"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.paused ? "Paused" : "Workout", systemImage: context.state.paused ? "pause.fill" : "dumbbell.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) { WorkoutLiveClock(state: context.state).font(.headline).frame(maxWidth: 100) }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.exercise).font(.caption).lineLimit(1).privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("\(context.state.loggedSets) done · \(context.state.skippedSets ?? 0) skipped / \(context.state.totalSets)")
                            Spacer(minLength: 4)
                            WorkoutLiveRest(state: context.state, stale: context.isStale)
                        }.font(.caption2).foregroundStyle(.secondary)
                        if !context.state.target.isEmpty { Text(context.state.target).font(.caption2).lineLimit(1).privacySensitive() }
                        WorkoutLiveSplit(state: context.state).font(.caption2).foregroundStyle(.secondary)
                        WorkoutLiveActions(sessionID: context.attributes.sessionID, state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.paused ? "pause.fill" : "dumbbell.fill").foregroundStyle(.orange)
            } compactTrailing: {
                WorkoutLiveClock(state: context.state).font(.caption2).frame(width: 66)
            } minimal: {
                Image(systemName: context.state.paused ? "pause.fill" : "dumbbell.fill").foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "fitout://widget/workout"))
            .keylineTint(.orange)
        }
    }
}

private struct WorkoutLiveLockScreen: View {
    let context: ActivityViewContext<WorkoutLiveAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(context.state.title, systemImage: "dumbbell.fill").font(.headline).lineLimit(1)
                    Text(context.state.exercise).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }.privacySensitive()
                Spacer(minLength: 8)
                WorkoutLiveClock(state: context.state).font(.title2.bold()).frame(maxWidth: 120)
            }
            HStack {
                Text("\(context.state.loggedSets)/\(context.state.totalSets) sets")
                Text("\(context.state.skippedSets ?? 0) skipped")
                Spacer(minLength: 4)
                WorkoutLiveRest(state: context.state, stale: context.isStale)
            }.font(.caption).foregroundStyle(.secondary)
            if !context.state.lastSet.isEmpty {
                Text("Last: \(context.state.lastSet)").font(.caption).lineLimit(1).privacySensitive()
            }
            WorkoutLiveSplit(state: context.state).font(.caption).foregroundStyle(.secondary)
            WorkoutLiveActions(sessionID: context.attributes.sessionID, state: context.state)
        }.padding(16).foregroundStyle(.white)
    }
}
private struct WorkoutLiveSplit: View {
    let state: WorkoutLiveAttributes.ContentState
    var body: some View {
        HStack(spacing: 6) {
            if let elapsed = state.setTimerElapsed {
                Image(systemName: "stopwatch")
                Text("Set")
                if let start = state.setTimerStart { Text(start, style: .timer).monospacedDigit() }
                else { Text(liveClock(elapsed)).monospacedDigit() }
            }
        }
    }
}

private struct WorkoutLiveClock: View {
    let state: WorkoutLiveAttributes.ContentState
    var body: some View {
        Group {
            if state.paused { Text(liveClock(state.elapsed)) }
            else { Text(state.clockStart, style: .timer) }
        }.monospacedDigit().contentTransition(.numericText())
            .accessibilityLabel(state.paused ? "Paused at \(liveClock(state.elapsed))" : "Workout elapsed time")
    }
}
private struct WorkoutLiveRest: View {
    let state: WorkoutLiveAttributes.ContentState
    let stale: Bool
    var body: some View {
        if state.paused && state.pausedRest > 0 { Text("Rest paused · \(liveClock(state.pausedRest))") }
        else if let deadline = state.restUntil {
            if stale { Text("Rest complete") }
            else {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                    Text(timerInterval: min(Date.now, deadline)...deadline, countsDown: true).monospacedDigit().frame(maxWidth: 65)
                }
            }
        }
    }
}
private struct WorkoutLiveActions: View {
    let sessionID: UUID
    let state: WorkoutLiveAttributes.ContentState
    var body: some View {
        HStack(spacing: 10) {
            action(state.paused ? "Resume" : "Pause", symbol: state.paused ? "play.fill" : "pause.fill", operation: state.paused ? "resume" : "pause")
            if state.restUntil != nil {
                action("+15s", symbol: "plus", operation: "extendRest").disabled(state.paused)
                action("Skip rest", symbol: "forward.end", operation: "endRest").disabled(state.paused)
            }
            else if !state.paused && ["ready", "exerciseTransition"].contains(state.phase ?? "") { action("Start set", symbol: "play", operation: "startSet") }
            else { Link(destination: URL(string: "fitout://widget/workout")!) { Image(systemName: "arrow.up.forward").frame(minWidth: 36, minHeight: 36) }.accessibilityLabel("Open workout") }
        }.buttonStyle(.bordered).tint(.orange)
    }
    private func action(_ title: String, symbol: String, operation: String) -> some View {
        Button(intent: WorkoutLiveIntent(sessionID: sessionID, commandID: state.revision, operation: operation)) {
            Label(title, systemImage: symbol).font(.caption).frame(minHeight: 32)
        }
    }
}
private func liveClock(_ seconds: TimeInterval) -> String {
    let value = Int(max(0, seconds))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
}

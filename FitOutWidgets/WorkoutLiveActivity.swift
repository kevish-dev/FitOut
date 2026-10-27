import SwiftUI
import WidgetKit
import ActivityKit

private enum LiveStyle {
    static let accent = Color(red: 1, green: 77.0 / 255, blue: 0)
    static let background = Color(red: 0.045, green: 0.045, blue: 0.055)
    static let secondary = Color.white.opacity(0.7)
    static let workoutURL = URL(string: "fitout://widget/workout")!
}

struct FitOutWorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutLiveAttributes.self) { context in
            WorkoutLiveLockScreen(state: context.state, sessionID: context.attributes.sessionID, stale: context.isStale)
                .activityBackgroundTint(LiveStyle.background)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(LiveStyle.workoutURL)
        } dynamicIsland: { context in
            let presentation = WorkoutLivePresentation(state: context.state, stale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(presentation.status, systemImage: presentation.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LiveStyle.accent).lineLimit(1)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutLiveClock(state: context.state, kind: .workout)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(width: 76, alignment: .trailing)
                        .foregroundStyle(.white).padding(.trailing, 4)
                }
                // No competing center region: the exercise gets the full width
                // below the camera rather than squeezing between two clocks.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        LiveExerciseHeading(state: context.state, presentation: presentation, lockScreen: false)
                        LiveCurrentWork(state: context.state, presentation: presentation, compact: true)
                        WorkoutLiveActions(sessionID: context.attributes.sessionID, state: context.state, presentation: presentation)
                    }.padding(.horizontal, 4).padding(.bottom, 2)
                }
            } compactLeading: {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiveStyle.accent)
                    .frame(width: 22, height: 24)
                    .accessibilityLabel(presentation.status)
            } compactTrailing: {
                WorkoutLiveClock(state: context.state, kind: presentation.resting ? .rest : .workout, compact: true)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(presentation.resting ? LiveStyle.accent : .white)
                    .frame(width: 44, height: 24)
                    .minimumScaleFactor(0.65)
            } minimal: {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiveStyle.accent)
                    .accessibilityLabel("FitOut · " + presentation.status)
            }
            .widgetURL(LiveStyle.workoutURL)
            .keylineTint(LiveStyle.accent)
        }
    }
}

/// Three compact rows; no redundant last-set row or unlabeled competing clocks.
private struct WorkoutLiveLockScreen: View {
    let state: WorkoutLiveAttributes.ContentState
    let sessionID: UUID
    let stale: Bool
    private var presentation: WorkoutLivePresentation { .init(state: state, stale: stale) }
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: presentation.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LiveStyle.accent)
                    .frame(width: 34, height: 34)
                    .background(LiveStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                LiveExerciseHeading(state: state, presentation: presentation, lockScreen: true)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.system(size: 10, weight: .medium)).foregroundStyle(LiveStyle.secondary)
                    WorkoutLiveClock(state: state, kind: .workout)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(width: 78, alignment: .trailing)
                }
            }
            LiveCurrentWork(state: state, presentation: presentation)
            WorkoutLiveActions(sessionID: sessionID, state: state, presentation: presentation)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .foregroundStyle(.white)
    }
}

private struct LiveExerciseHeading: View {
    let state: WorkoutLiveAttributes.ContentState
    let presentation: WorkoutLivePresentation
    let lockScreen: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.exercise)
                    .font(.system(size: lockScreen ? 15 : 14, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail)
                if lockScreen {
                    Text(state.title).font(.system(size: 11)).foregroundStyle(LiveStyle.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).privacySensitive()
            if !lockScreen, let progress = presentation.exerciseProgress {
                Text(progress).font(.system(size: 11, weight: .medium)).foregroundStyle(LiveStyle.secondary)
                    .accessibilityLabel("Exercise " + progress.replacingOccurrences(of: "/", with: " of "))
            }
        }
    }
}

private struct LiveCurrentWork: View {
    let state: WorkoutLiveAttributes.ContentState
    let presentation: WorkoutLivePresentation
    var compact = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if presentation.restFinished || !presentation.resting && !presentation.setTimerVisible {
                    Text(state.paused ? "Paused" : presentation.restFinished ? "Ready" : state.phase == "exerciseTransition" ? "Next" : "Ready")
                        .font(.system(size: compact ? 19 : 22, weight: .semibold, design: .rounded))
                } else {
                    WorkoutLiveClock(state: state, kind: presentation.resting ? .rest : presentation.setTimerVisible ? .set : .workout)
                        .font(.system(size: compact ? 23 : 25, weight: .semibold, design: .rounded))
                        .frame(width: compact ? 88 : 100, alignment: .leading)
                }
                if presentation.resting || presentation.setTimerVisible {
                    Text(presentation.resting ? (state.paused ? "paused" : "rest") : "set")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(LiveStyle.secondary)
                }
            }.foregroundStyle(presentation.resting ? LiveStyle.accent : .white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .trailing, spacing: 3) {
                Text(presentation.setProgress).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(presentation.secondaryDetail).font(.system(size: 12)).foregroundStyle(LiveStyle.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .trailing).privacySensitive()
        }.frame(minHeight: 34)
        .accessibilityElement(children: .combine)
    }
}

private enum LiveClockKind { case workout, set, rest }

/// System-rendered timer text has bounded width and a stable interval. A rest
/// countdown ends at zero; it never becomes an increasing overtime timer.
private struct WorkoutLiveClock: View {
    let state: WorkoutLiveAttributes.ContentState
    let kind: LiveClockKind
    var compact = false
    var body: some View {
        text
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(kind == .rest ? "Rest time remaining" : kind == .set ? "Current set elapsed time" : "Total workout time")
            .accessibilityValue(text)
    }
    private var text: Text {
        switch kind {
            case .rest:
                if state.paused { return Text(WorkoutLivePresentation.clock(state.pausedRest, compact: compact)) }
                else if let end = state.restUntil {
                    let start = min(state.restStartedAt ?? end.addingTimeInterval(-3600), end)
                    return Text(timerInterval: start...end, countsDown: true, showsHours: !compact)
                } else { return Text("00:00") }
            case .set:
                if state.paused || state.setTimerStart == nil {
                    return Text(WorkoutLivePresentation.clock(state.setTimerElapsed ?? 0, compact: compact))
                }
                return Text(state.setTimerStart ?? state.clockStart, style: .timer)
            case .workout:
                if state.paused { return Text(WorkoutLivePresentation.clock(state.elapsed, compact: compact)) }
                else { return Text(state.clockStart, style: .timer) }
        }
    }
}

private struct WorkoutLiveActions: View {
    let sessionID: UUID
    let state: WorkoutLiveAttributes.ContentState
    let presentation: WorkoutLivePresentation
    var body: some View {
        HStack(spacing: 8) {
            action(state.paused ? "Resume workout" : "Pause workout", symbol: state.paused ? "play.fill" : "pause.fill", operation: state.paused ? "resume" : "pause", iconOnly: true)
                .frame(width: 44)
            if presentation.resting && !state.paused && !presentation.restFinished {
                action("+15 sec", symbol: "plus", operation: "extendRest")
                    .frame(width: 76)
            }
            switch presentation.primaryAction {
            case .open:
                Link(destination: LiveStyle.workoutURL) {
                    actionLabel("Open workout", symbol: "arrow.up.right", primary: true)
                }.accessibilityLabel("Open current workout in FitOut")
            case .startSet:
                action(presentation.primaryTitle, symbol: "play.fill", operation: "startSet", primary: true)
            case .endRest:
                action(presentation.primaryTitle, symbol: "forward.end.fill", operation: "endRest", primary: true)
            }
        }
        .buttonStyle(.plain)
    }
    private func action(_ title: String, symbol: String, operation: String, primary: Bool = false, iconOnly: Bool = false) -> some View {
        Button(intent: WorkoutLiveIntent(sessionID: sessionID, commandID: state.revision, operation: operation)) {
            actionLabel(title, symbol: symbol, primary: primary, iconOnly: iconOnly)
        }.accessibilityLabel(title)
    }
    private func actionLabel(_ title: String, symbol: String, primary: Bool, iconOnly: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            if !iconOnly { Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8) }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(primary ? Color.black : Color.white)
        .background(primary ? LiveStyle.accent : Color.white.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
}

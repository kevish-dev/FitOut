import SwiftUI

/// Presentation only. The persisted session remains the authority for all clocks.
struct WorkoutStageTiming {
    let seconds: TimeInterval
    let progress: Double
    let title: String
    let detail: String
    let symbol: String
    let isResting: Bool

    init(session: WorkoutSession, entry: WorkoutEntry, set: WorkoutSet, now: Date) {
        let phase = session.execution?.phase ?? .ready
        let paused = phase == .paused
        isResting = phase == .resting || (paused && session.execution?.resumePhase == .resting)
        let elapsed = session.setElapsed(set, at: now) ?? 0
        if isResting {
            let remaining = session.restRemaining(at: now)
            seconds = ceil(remaining)
            // Active seconds exclude pauses. Extending rest grows the budget too.
            let sinceCompletion = max(0, session.duration(at: now) - (set.loggedActiveSeconds ?? session.duration(at: set.completedAt ?? now)))
            let budget = remaining + sinceCompletion
            progress = budget > 0 ? min(1, max(0, remaining / budget)) : 0
            title = paused ? "Rest paused" : "Rest remaining"
            detail = "Last set · " + WorkoutDisplay.clock(elapsed)
            symbol = paused ? "pause.fill" : "hourglass"
        } else {
            seconds = elapsed
            let target = set.status == .pending ? set.seconds : (set.inputTarget?.seconds ?? set.plannedTarget?.seconds ?? set.seconds)
            if entry.exercise.kind == .duration, target > 0 {
                progress = min(1, max(0, elapsed / target))
                detail = "Target · " + WorkoutDisplay.clock(target)
            } else {
                progress = session.setProgress
                detail = session.skippedSets.isEmpty ? "\(session.completedSets.count)/\(session.trackedSetCount) sets logged" : "\(session.completedSets.count) logged · \(session.skippedSets.count) skipped"
            }
            switch phase {
            case .paused: title = "Set paused"; symbol = "pause.fill"
            case .ready, .exerciseTransition: title = "Ready to start"; symbol = "play.fill"
            default: title = "Set time"; symbol = "flame.fill"
            }
        }
    }
}

/// The image, pause control and clock form one stage instead of separate cards.
struct FocusedWorkoutStage: View {
    let session: WorkoutSession
    let entry: WorkoutEntry
    let set: WorkoutSet
    let availableHeight: CGFloat
    let now: () -> Date
    let togglePause: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var phase: WorkoutPhase { session.execution?.phase ?? .ready }
    private var canPause: Bool { [.activeSet, .resting, .paused].contains(phase) }
    private var stageBudget: CGFloat { min(440, max(300, availableHeight - 250)) }

    var body: some View {
        VStack(spacing: 0) {
            ExerciseImageButton(exercise: entry.exercise, style: .workoutStage(typeSize.isAccessibilitySize ? 240 : stageBudget * 0.48))
                .overlay(alignment: .bottom) {
                    if canPause {
                        Button(action: togglePause) {
                            Label(phase == .paused ? "Resume" : "Pause", systemImage: phase == .paused ? "play.fill" : "pause.fill")
                                .font(FitTheme.button(15)).padding(.horizontal, 22).frame(minHeight: 46)
                        }
                        .buttonStyle(.plain).dashboardGlass(in: Capsule(), interactive: true)
                        .accessibilityLabel(phase == .paused ? "Resume workout" : "Pause workout")
                        .accessibilityIdentifier("pauseResumeWorkout")
                        .offset(y: 20)
                    }
                }.zIndex(1)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let timing = WorkoutStageTiming(session: session, entry: entry, set: set, now: now())
                WorkoutStageClock(timing: timing, height: stageBudget * 0.34, animate: !reduceMotion && phase != .paused)
            }
            .padding(.top, canPause ? 34 : 20)
            .padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .accessibilityIdentifier("focusedWorkoutStage")
    }
}

private struct WorkoutStageClock: View {
    let timing: WorkoutStageTiming
    let height: CGFloat
    let animate: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                WorkoutTimerArc().stroke(FitTheme.textPrimary.opacity(0.13), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                WorkoutTimerArc(fraction: timing.progress)
                    .stroke(FitTheme.dashboardAccent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .animation(animate ? .linear(duration: 0.8) : nil, value: timing.progress)
                WorkoutArcMarker(progress: timing.progress, symbol: timing.symbol)
                    .animation(animate ? .linear(duration: 0.8) : nil, value: timing.progress)
                VStack(spacing: 8) {
                    Text(timing.title).font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
                    Text(WorkoutDisplay.clock(timing.seconds)).font(FitTheme.metric(typeSize.isAccessibilitySize ? 46 : height < 125 ? 40 : 48))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
                        .contentTransition(.identity)
                }.padding(.horizontal, 28).padding(.bottom, 14)
            }
            .frame(height: typeSize.isAccessibilitySize ? 196 : height)
            Text(timing.detail).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timing.title)
        .accessibilityValue(WorkoutDisplay.clock(timing.seconds) + ", " + timing.detail)
        .accessibilityIdentifier("focusedSetClock")
    }
}

private struct WorkoutTimerArc: Shape {
    var fraction: Double = 1
    var animatableData: Double { get { fraction } set { fraction = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: .zero, radius: 1, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fraction), clockwise: false)
        return path.applying(CGAffineTransform(a: max(0, rect.width / 2 - 8), b: 0, c: 0,
            d: max(0, rect.height - 8), tx: rect.midX, ty: rect.maxY - 8))
    }
}

/// Use the same angle as the arc, including on compressed screens and during animation.
private struct WorkoutArcMarker: View, Animatable {
    nonisolated var progress: Double
    let symbol: String
    nonisolated var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        GeometryReader { geometry in
            let radiusX = max(0, geometry.size.width / 2 - 8)
            let radiusY = max(0, geometry.size.height - 8)
            let angle = Double.pi + Double.pi * progress
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white).frame(width: 42, height: 42)
                .background(FitTheme.dashboardAccent, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 2) }
                .position(x: geometry.size.width / 2 + radiusX * cos(angle), y: geometry.size.height - 8 + radiusY * sin(angle))
        }
    }
}

struct FocusedWorkoutMetrics: View {
    let session: WorkoutSession
    let unit: WeightUnit
    let now: () -> Date
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                metric("\(session.completedSets.count)", label: "Sets logged")
                if !typeSize.isAccessibilitySize { Divider().frame(height: 36) }
                metric(unit.display(session.volumeKG).formatted(.number.precision(.fractionLength(0...1))), label: unit.rawValue + "·reps")
                if !typeSize.isAccessibilitySize { Divider().frame(height: 36) }
                metric(WorkoutDisplay.clock(session.duration(at: now())), label: "Workout time")
            }
        }.padding(.vertical, 8)
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(FitTheme.strong(21)).monospacedDigit().foregroundStyle(FitTheme.dashboardAccent)
                .lineLimit(1).minimumScaleFactor(0.65)
            Text(label).font(FitTheme.body(10)).foregroundStyle(FitTheme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

/// Previewing the next item never advances or mutates the session.
struct WorkoutActionPreview {
    let detail: String?
    init(session: WorkoutSession) {
        let phase = session.execution?.phase ?? .ready
        guard phase != .workoutCompleted else { detail = nil; return }
        guard let current = session.executingWork else {
            detail = session.entries.isEmpty ? "Choose exercises and log as you train." : "Your recorded sets are saved."; return
        }
        if phase == .paused { detail = "Your set and rest timers are paused."; return }
        let starting = phase == .ready || phase == .exerciseTransition
        let pending = session.pendingWork.first { starting ? $0.setID == current.set.id : $0.setID != current.set.id }
        guard let pending, let entry = session.entries.first(where: { $0.id == pending.entryID }),
              let index = entry.sets.firstIndex(where: { $0.id == pending.setID }) else {
            detail = "Final set · Workout summary follows"; return
        }
        detail = (starting ? "" : "Next · ") + entry.exercise.name + " · Set \(index + 1) of \(entry.sets.count)"
    }
}

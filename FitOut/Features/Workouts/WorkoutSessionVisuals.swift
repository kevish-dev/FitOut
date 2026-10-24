import SwiftUI

enum WorkoutDisplay {
    static func clock(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct QuickWorkoutLaunchCard: View {
    let active: WorkoutSession?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        cardLayout {
            Image("RoutineEquipment").resizable().scaledToFit().frame(width: 90, height: 82).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(active == nil ? "Quick workout" : "Continue your session").font(FitTheme.section(17))
                Text(active.map { "\($0.completedSets.count) sets logged · \($0.status == .paused ? "Paused" : "In progress")" } ?? "Choose exercises and sets before you start.")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .medium)).foregroundStyle(FitTheme.dashboardAccent)
        }
        .padding(FitTheme.cardInset).frame(maxWidth: .infinity, minHeight: 110)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 22), interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
    private var cardLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }
}

struct WorkoutSessionHero: View {
    let session: WorkoutSession
    let unit: WeightUnit
    let now: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                Circle().fill(session.status == .paused ? FitTheme.textSecondary : FitTheme.dashboardAccent).frame(width: 6, height: 6)
                Text(session.status == .paused ? "Session paused" : session.isActive ? "Live session" : session.status == .completed ? "Workout logged" : "Workout \(session.status.rawValue)")
                    .font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
            }
            Text(session.title).font(FitTheme.display(24)).fixedSize(horizontal: false, vertical: true)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { elapsed; graphic.frame(maxWidth: .infinity) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { elapsed; Spacer(minLength: 0); graphic }
                    VStack(alignment: .leading, spacing: 16) { elapsed; graphic.frame(maxWidth: .infinity) }
                }
            }
            if !session.entries.isEmpty {
                metricLayout {
                    metric("\(session.completedSets.count)", label: "Sets logged")
                    metric("\(session.entries.count)", label: "Exercises")
                    if session.entries.contains(where: { $0.exercise.kind == .weighted }) {
                        metric(unit.display(session.volumeKG).formatted(.number.precision(.fractionLength(0...1))), label: "\(unit.rawValue)·reps")
                    } else {
                        metric("\(session.isActive ? session.remainingSetCount : session.completedExercises)", label: session.isActive ? "Sets remaining" : "Exercises logged")
                    }
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(FitTheme.textPrimary.opacity(0.07), lineWidth: 1) }
    }
    private var metricLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    }
    private var elapsed: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(WorkoutDisplay.clock(session.duration(at: now))).font(FitTheme.metric(28)).monospacedDigit()
            Text("Active time").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
        }.accessibilityElement(children: .combine)
    }
    @ViewBuilder private var graphic: some View {
        if session.entries.isEmpty {
            Image("RoutineEquipment").resizable().scaledToFit().frame(width: 140, height: 104).accessibilityHidden(true)
        } else {
            ZStack {
                Circle().stroke(FitTheme.textPrimary.opacity(0.07), lineWidth: 6)
                Circle().trim(from: 0, to: session.setProgress).stroke(FitTheme.dashboardAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: session.setProgress)
                VStack(spacing: 3) {
                    Text(session.trackedSetCount == 0 ? "0" : "\(session.completedSets.count)/\(session.trackedSetCount)").font(FitTheme.strong(17)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text("sets").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }
            }.frame(width: 86, height: 86).padding(3)
                .accessibilityLabel("\(session.completedSets.count) logged sets, \(session.remainingSetCount) remaining")
        }
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(FitTheme.strong(18)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

struct WorkoutRestCard: View {
    let session: WorkoutSession
    let now: Date
    let end: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var remaining: TimeInterval { session.restRemaining(at: now) }
    private var progress: Double { session.currentRestDuration > 0 ? min(1, remaining / session.currentRestDuration) : 0 }
    var body: some View {
        cardLayout {
            ZStack {
                Circle().stroke(FitTheme.textPrimary.opacity(0.08), lineWidth: 4)
                Circle().trim(from: 0, to: progress).stroke(FitTheme.dashboardAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    .animation(reduceMotion || session.status == .paused ? nil : .linear(duration: 1), value: progress)
                Image(systemName: "timer").font(.system(size: 20)).foregroundStyle(FitTheme.dashboardAccent)
            }.frame(width: 48, height: 48).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.status == .paused ? "Rest paused" : "Rest between sets").font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
                Text(WorkoutDisplay.clock(ceil(remaining))).font(FitTheme.metric(23)).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("End rest", action: end).font(FitTheme.button(13)).frame(minWidth: 70, minHeight: 44)
                .accessibilityIdentifier("endWorkoutRest")
        }
        .padding(FitTheme.cardInset).dashboardGlass(in: RoundedRectangle(cornerRadius: 22))
    }
    private var cardLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
    }
}

struct WorkoutEmptyState: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                Image(systemName: "square.grid.2x2")
                Capsule().fill(FitTheme.subtleBorder).frame(width: 20, height: 2)
                Image(systemName: "slider.horizontal.3")
                Capsule().fill(FitTheme.subtleBorder).frame(width: 20, height: 2)
                Image(systemName: "checkmark.circle")
            }.font(.system(size: 25, weight: .light)).foregroundStyle(FitTheme.dashboardAccent)
                .padding(.vertical, 18).accessibilityHidden(true)
            Text("Choose your movements").font(FitTheme.section(21))
            Text("Pick exercises, then log each set as you train.")
                .font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 16)
    }
}

import SwiftUI

struct RoutineStageBar: View {
    @Binding var selection: RoutineEditorStage
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 4) { stages }
            } else {
                HStack(spacing: 4) { stages }
            }
        }
        .padding(5)
        .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("routineStages")
    }

    private var stages: some View {
        ForEach(RoutineEditorStage.allCases) { stage in
            let selected = selection == stage
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { selection = stage }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: stage.editorSymbol).font(.system(size: 14, weight: .medium))
                    Text(stage.rawValue).font(FitTheme.medium(12))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(selected ? FitTheme.textPrimary : FitTheme.textSecondary)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(FitTheme.dashboardAccent.opacity(0.16))
                            .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(FitTheme.dashboardAccent.opacity(0.5), lineWidth: 1) }
                            .matchedGeometryEffect(id: "stage", in: highlight)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(RoutineEditorPressStyle())
            .accessibilityIdentifier("routineStage-\(stage.rawValue.lowercased())")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

struct RoutinePlanHero: View {
    let routine: Routine
    var reviewing = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var exercises: [PlannedExercise] { routine.trainingDays.flatMap(\.exercises) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { title; gear.frame(maxWidth: .infinity) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { title.frame(minWidth: 144); gear }
                    VStack(alignment: .leading, spacing: 12) { gear.frame(maxWidth: .infinity); title }
                }
            }
            metricLayout {
                metric("\(routine.trainingDays.count)", title: "Training days")
                if !typeSize.isAccessibilitySize { Divider().frame(height: 30).overlay(FitTheme.textPrimary.opacity(0.08)) }
                metric("\(exercises.count)", title: "Exercises")
                if !typeSize.isAccessibilitySize { Divider().frame(height: 30).overlay(FitTheme.textPrimary.opacity(0.08)) }
                metric("\(exercises.reduce(0) { $0 + $1.setCount })", title: "Planned sets")
            }
        }
        .padding(FitTheme.cardInset)
        .background {
            RoundedRectangle(cornerRadius: 24).fill(FitTheme.surface)
        }
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(FitTheme.textPrimary.opacity(0.06), lineWidth: 1) }
    }

    private var metricLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 0))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reviewing ? "WEEKLY OVERVIEW" : "ROUTINE BUILDER")
                .font(FitTheme.medium(10)).tracking(1.2).foregroundStyle(FitTheme.dashboardAccent)
            Text(reviewing ? "Your week,\nall together." : "Build your\ntraining week.")
                .font(FitTheme.display(21)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var gear: some View {
        Image("RoutineEquipment").resizable().scaledToFit()
            .frame(width: 146, height: 122).accessibilityHidden(true)
    }
    private func metric(_ value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(FitTheme.metric(23)).monospacedDigit().contentTransition(.numericText())
            Text(title).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

struct RoutineDayKindControl: View {
    @Binding var selection: RoutineDayKind
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { VStack(spacing: 6) { choices } }
            else { HStack(spacing: 6) { choices } }
        }
    }
    private var choices: some View {
        ForEach(RoutineDayKind.allCases, id: \.self) { kind in
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = kind }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: kind.editorSymbol).font(.system(size: 19, weight: .regular))
                    Text(kind == .flexible ? "Open" : kind == .rest ? "Rest" : "Workout").font(FitTheme.medium(12))
                }
                .frame(maxWidth: .infinity, minHeight: 76)
                .foregroundStyle(selection == kind ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                .dashboardGlass(in: RoundedRectangle(cornerRadius: 16), highlighted: selection == kind, interactive: true)
            }
            .buttonStyle(RoutineEditorPressStyle())
            .accessibilityLabel(kind.rawValue)
            .accessibilityAddTraits(selection == kind ? .isSelected : [])
        }
    }
}

struct RoutineReviewDay: View {
    let day: RoutineDay
    let exercise: ExerciseDefinition?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        cardLayout {
            if typeSize.isAccessibilitySize {
                Label(RoutineSchedule.weekdays[day.weekday], systemImage: day.kind.editorSymbol)
                    .font(FitTheme.medium(13)).foregroundStyle(FitTheme.dashboardAccent)
            } else {
                VStack(spacing: 8) {
                    Text(String(RoutineSchedule.weekdays[day.weekday].prefix(3))).font(FitTheme.medium(12))
                    Image(systemName: day.kind.editorSymbol).font(.system(size: 13))
                }
                .foregroundStyle(day.kind == .workout ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                .frame(width: 34)
            }
            if day.kind == .workout && !typeSize.isAccessibilitySize {
                ExerciseArtwork(exercise: exercise, size: 52)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(day.kind == .workout ? day.title : day.kind == .rest ? "Rest day" : "Open day").font(FitTheme.section(15))
                Text(day.kind == .workout ? "\(day.exercises.count) exercises · \(day.exercises.reduce(0) { $0 + $1.setCount }) sets" : "No workout scheduled")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                if day.kind == .workout && day.exercises.isEmpty {
                    Text("Add exercises").font(FitTheme.medium(11)).foregroundStyle(FitTheme.dashboardAccent)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(FitTheme.textSecondary)
        }
        .padding(FitTheme.cardInset).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(FitTheme.surface.opacity(day.kind == .workout ? 1 : 0.55), in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .leading) {
            if day.kind == .workout {
                Capsule().fill(FitTheme.dashboardAccent).frame(width: 3, height: 28).padding(.leading, 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
    private var cardLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
    }
}

struct RoutineDayPauseGraphic: View {
    let kind: RoutineDayKind
    let hasExercises: Bool
    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().stroke(FitTheme.textPrimary.opacity(0.04), lineWidth: 1).frame(width: 158, height: 158)
                Circle().stroke(FitTheme.textPrimary.opacity(0.07), lineWidth: 1).frame(width: 122, height: 122)
                Image(systemName: kind == .rest ? "moon.zzz" : "calendar.badge.plus")
                    .font(.system(size: 46, weight: .ultraLight)).foregroundStyle(FitTheme.dashboardAccent)
                    .frame(width: 88, height: 88).dashboardGlass(in: Circle())
            }.accessibilityHidden(true)
            Text(kind == .rest ? "Room to recover" : "Keep this day open").font(FitTheme.section(21))
            Text(hasExercises ? "Your exercises are kept here. Switch back to Workout to use them." : "You can change the day type whenever your schedule changes.")
                .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct RoutineEditorPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(.interaction, Rectangle())
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(FitMotion.press(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

extension RoutineEditorStage {
    var editorSymbol: String {
        switch self { case .schedule: "calendar"; case .workouts: "dumbbell"; case .review: "checklist" }
    }
}

extension RoutineDayKind {
    var editorSymbol: String {
        switch self { case .workout: "dumbbell"; case .rest: "moon"; case .flexible: "circle.dashed" }
    }
}

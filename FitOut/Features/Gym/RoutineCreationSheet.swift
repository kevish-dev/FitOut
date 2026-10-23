import SwiftUI

/// Selection and editing share a presentation, avoiding overlapping sheets.
struct RoutineCreationSheet: View {
    let store: GymStore
    var unit: WeightUnit = .kg
    var initialWeekday: Int?
    var useAsActive = true
    @State private var selected: RoutineTemplate = .custom
    @State private var editing: Routine?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var preview: Routine { selected.make() }

    var body: some View {
        Group {
            if let editing {
                RoutineEditor(store: store, routine: editing, initialWeekday: initialWeekday, unit: unit)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                        header
                        choice(.custom)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Or start with a template").font(FitTheme.section(16))
                            VStack(spacing: 0) {
                                ForEach(RoutineTemplate.allCases.filter { $0 != .custom }) { template in
                                    choice(template)
                                    if template != RoutineTemplate.allCases.last {
                                        Divider().overlay(.white.opacity(0.06)).padding(.horizontal, FitTheme.cardInset)
                                    }
                                }
                            }
                            .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                        }
                        Text("Templates include exercises and sets. Change anything in the next step.")
                            .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                    }
                    .padding(FitTheme.pageInset)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
                .background(FitTheme.dashboardBackground)
            }
        }
        .foregroundStyle(.white).tint(FitTheme.dashboardAccent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .presentationBackground(FitTheme.dashboardBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("Create a\nworkout routine")
                    .font(FitTheme.display(25)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .dashboardGlass(in: Circle(), interactive: true)
                }.buttonStyle(.plain).accessibilityLabel("Cancel routine creation")
                    .accessibilityIdentifier("cancelRoutineCreation")
            }
            Text("Choose a starting point for your week.")
                .font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
        }.padding(.top, 8)
    }

    private func choice(_ template: RoutineTemplate) -> some View {
        let isSelected = selected == template
        let sample = template.make()
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selected = template }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if template == .custom {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(FitTheme.dashboardAccent)
                        .frame(width: 40, height: 44)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(template == .custom ? "Build from scratch" : template.rawValue)
                        .font(FitTheme.section(15))
                    Text(template == .custom ? "Pick your own days and exercises" : "\(sample.trainingDays.count) days / week · \(template.creationDetail)")
                        .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isSelected ? FitTheme.dashboardAccent : FitTheme.textSecondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(FitTheme.cardInset)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(isSelected ? FitTheme.dashboardAccent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(FitTheme.dashboardAccent.opacity(0.7), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(RoutineChoicePressStyle())
        .background(template == .custom ? FitTheme.surface : .clear, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel(template == .custom ? "Build from scratch" : template.rawValue)
        .accessibilityValue(template == .custom ? "Your own schedule" : "\(sample.trainingDays.count) training days per week. \(template.creationDetail)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if selected != .custom {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) { previewTitle; weekMarkers }
                } else {
                    HStack(alignment: .center, spacing: 16) { previewTitle; Spacer(minLength: 0); weekMarkers }
                }
            }
            Button {
                var routine = selected.make()
                if selected == .custom { routine.name = "My training plan" }
                routine.isActive = useAsActive
                editing = routine
            } label: {
                HStack(spacing: 12) {
                    Text(selected == .custom ? "Build my routine" : "Use this template")
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.right")
                }
                .font(FitTheme.button(16)).padding(.horizontal, 18)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(RoutineChoicePressStyle())
            .accessibilityIdentifier("createRoutineContinue")
        }
        .padding(FitTheme.pageInset)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var previewTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Week preview").font(FitTheme.medium(12))
            Text("\(preview.trainingDays.count) training days").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
        }
    }

    private var weekMarkers: some View {
        HStack(spacing: 9) {
            ForEach(preview.days.sorted { $0.weekday < $1.weekday }) { day in
                VStack(spacing: 6) {
                    Text(String(RoutineSchedule.weekdays[day.weekday].prefix(1))).font(FitTheme.medium(11))
                    Circle().fill(day.kind == .workout ? FitTheme.dashboardAccent : FitTheme.textSecondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training on " + preview.trainingDays.map { RoutineSchedule.weekdays[$0.weekday] }.joined(separator: ", "))
    }
}

private struct RoutineChoicePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension RoutineTemplate {
    var creationDetail: String {
        switch self {
        case .custom: "Your schedule"
        case .ppl: "Push, pull and leg sessions"
        case .upperLower: "Alternate upper and lower body"
        case .fullBody: "Whole-body sessions"
        case .arnold: "Chest/back, arms/shoulders, legs"
        case .bro: "One muscle group each day"
        }
    }
}

import SwiftUI

struct GoalsScreen: View {
    @Binding var profile: FitnessProfile
    var scale: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "Your Fitness", accent: "Goals", size: 31 * scale)
                .padding(.bottom, 46 * scale)
            VStack(spacing: 16 * scale) {
                HStack(spacing: 10) { goal(.muscle); goal(.strength) }
                HStack(spacing: 10) { goal(.endurance); goal(.fatLoss) }
                goal(.mobility)
                HStack(spacing: 10) { goal(.shape); goal(.health) }
                goal(.recovery).frame(maxWidth: 204 * scale)
            }
            if profile.goals.isEmpty {
                Text("Choose at least one goal to continue.")
                    .font(FitTheme.body(13))
                    .foregroundStyle(FitTheme.orange)
                    .padding(.top, 18)
            }
        }
    }

    private func goal(_ goal: FitnessGoal) -> some View {
        let selected = profile.goals.contains(goal)
        return Button {
            if selected { profile.goals.remove(goal) } else { profile.goals.insert(goal) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12 * scale) {
                Image(systemName: goal.symbol)
                    .font(.system(size: 21 * scale, weight: .semibold))
                Text(goal.title)
                    .font(FitTheme.button(13 * scale))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .layoutPriority(1)
            }
            .foregroundStyle(selected ? FitTheme.orange : FitTheme.textPrimary)
            .padding(.horizontal, 14 * scale)
            .frame(maxWidth: .infinity)
            .frame(height: 51 * scale)
            .fitSurface(selected: selected, radius: 15)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goal.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("goal-\(goal.rawValue)")
    }
}

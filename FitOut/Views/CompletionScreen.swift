import SwiftUI

struct CompletionScreen: View {
    @Bindable var store: OnboardingStore
    private var weightSummary: String {
        let profile = store.profile
        return "\(profile.unit.display(profile.currentWeightKG).formatted(.number.precision(.fractionLength(0...1)))) → \(profile.unit.display(profile.targetWeightKG).formatted(.number.precision(.fractionLength(0...1)))) \(profile.unit.rawValue)"
    }
    private var exportText: String {
        "FitOut · \(store.profile.name)\nAge: \(store.profile.age)\nWeight: \(weightSummary)\nGoals: \(FitnessGoal.allCases.filter { store.profile.goals.contains($0) }.map(\.title).joined(separator: ", "))"
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(FitTheme.orange)
                    .padding(.top, 30)
                ScreenHeading(first: "Your journey", accent: "starts now.")
                AvatarView(profile: store.profile, size: 90)
                Text("You’re ready, \(store.profile.name).")
                    .font(FitTheme.label(18)).multilineTextAlignment(.center)
                Text("Your profile and goals are saved on this iPhone.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                VStack(spacing: 18) {
                    summaryRow("Profile", value: "\(store.profile.gender.rawValue) · \(store.profile.age) years")
                    Divider()
                    summaryRow("Current → target", value: weightSummary)
                }.padding(20).fitSurface()
                VStack(alignment: .leading, spacing: 16) {
                    Text("YOUR GOALS").font(FitTheme.body(13)).tracking(2).foregroundStyle(.white.opacity(0.5))
                    ForEach(FitnessGoal.allCases.filter { store.profile.goals.contains($0) }) { goal in
                        Label(goal.title, systemImage: goal.symbol)
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(FitTheme.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20).fitSurface()
                Button { store.editProfile() } label: {
                    Label("Edit my profile", systemImage: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .foregroundStyle(FitTheme.orange).fitSurface(selected: true)
                }.buttonStyle(.plain).accessibilityIdentifier("editProfileButton")
                ShareLink(item: exportText) {
                    Label("Share my goals", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                }.padding(.bottom, 20)
            }.padding(.horizontal, 28).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }.scrollIndicators(.hidden).accessibilityIdentifier("completionScreen")
    }
    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }.font(.system(size: 14, weight: .medium))
    }
}

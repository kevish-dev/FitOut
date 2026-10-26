import SwiftUI

struct GenderAgeScreen: View {
    @Environment(\.fitHaptics) private var haptics
    @Binding var profile: FitnessProfile
    var scale: CGFloat = 1
    var selectedGender: Gender? = nil
    var onGenderSelected: ((Gender) -> Void)? = nil
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "What’s your", accent: "gender?", size: 30 * scale)
                .padding(.bottom, 24 * scale)
            VStack(spacing: 10) {
                ForEach(Gender.allCases, id: \.self) { gender in
                    let selected = onGenderSelected == nil ? profile.gender == gender : selectedGender == gender
                    Button {
                        if let onGenderSelected { onGenderSelected(gender) }
                        else { profile.gender = gender }
                        haptics?.play(.selection)
                    } label: {
                        VStack(spacing: 2) {
                            Text(gender == .male ? "♂" : "♀")
                                .font(.system(size: 86 * scale, weight: .regular))
                                .frame(height: 82 * scale)
                            Text(gender.rawValue).font(FitTheme.button(17 * scale))
                        }
                        .foregroundStyle(selected ? FitTheme.orange : FitTheme.textPrimary)
                        .frame(width: 192 * scale, height: 136 * scale)
                        .fitSurface(selected: selected, radius: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(gender.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Your age").font(FitTheme.section(16 * scale))
                .padding(.top, 18 * scale).padding(.bottom, 12 * scale)
            AgeWheel(age: $profile.age)
                .frame(width: 146 * scale, height: 136 * scale)
        }
    }
}

struct AgeWheel: View {
    @Environment(\.fitHaptics) private var haptics
    @Binding var age: Int
    @State private var selectedAge: Int?
    @State private var isScrolling = false
    private let rowHeight: CGFloat = 27

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(13...100, id: \.self) { value in
                            Text("\(value)")
                                .font(selectedAge == value ? FitTheme.display(27) : FitTheme.body(22))
                                .foregroundStyle(selectedAge == value ? FitTheme.orange : FitTheme.textPrimary.opacity(0.4))
                                .frame(maxWidth: .infinity).frame(height: rowHeight)
                                .id(value)
                        }
                    }
                    .scrollTargetLayout()
                }
                .safeAreaPadding(.vertical, max(0, (geometry.size.height - rowHeight) / 2))
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedAge, anchor: .center)
                .onScrollPhaseChange { _, phase in
                    isScrolling = phase != .idle
                    if phase == .idle, let selectedAge, selectedAge != age {
                        age = selectedAge
                        haptics?.play(.selection)
                    }
                }
                .onAppear { selectedAge = age }
                .onChange(of: age) { _, value in if !isScrolling { selectedAge = value } }
                .onDisappear {
                    if isScrolling, let selectedAge { age = selectedAge }
                }
                HStack {
                    Capsule().fill(FitTheme.orange).frame(width: 2.5)
                    Spacer()
                    Capsule().fill(FitTheme.orange).frame(width: 2.5)
                }
                .frame(height: 39)
                .background { VStack { Divider(); Spacer(); Divider() }.opacity(0.35) }
                .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .mask { LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom) }
        }
        .fitSurface(radius: 23)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your age")
        .accessibilityValue("\(selectedAge ?? age) years")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: age = min(100, age + 1)
            case .decrement: age = max(13, age - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("agePicker")
    }
}

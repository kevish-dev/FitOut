import SwiftUI

struct GenderAgeScreen: View {
    @Binding var profile: FitnessProfile
    var scale: CGFloat = 1
    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "What’s your", accent: "gender?", size: 30 * scale)
                .padding(.bottom, 24 * scale)
            VStack(spacing: 10) {
                ForEach(Gender.allCases, id: \.self) { gender in
                    let selected = profile.gender == gender
                    Button {
                        profile.gender = gender
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 2) {
                            Text(gender == .male ? "♂" : "♀")
                                .font(.system(size: 86 * scale, weight: .regular))
                                .frame(height: 82 * scale)
                            Text(gender.rawValue).font(FitTheme.label(17 * scale))
                        }
                        .foregroundStyle(selected ? FitTheme.orange : .white)
                        .frame(width: 192 * scale, height: 136 * scale)
                        .fitSurface(selected: selected, radius: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(gender.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Your age").font(FitTheme.label(16 * scale))
                .padding(.top, 18 * scale).padding(.bottom, 12 * scale)
            AgeWheel(age: $profile.age)
                .frame(width: 146 * scale, height: 136 * scale)
        }
    }
}

struct AgeWheel: View {
    @Binding var age: Int
    @GestureState private var dragOffset: CGFloat = 0
    private let rowHeight: CGFloat = 27

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(-3...3, id: \.self) { delta in
                    let value = age + delta
                    if (13...100).contains(value) {
                        let distance = abs(CGFloat(delta) * rowHeight + dragOffset)
                        Text("\(value)")
                            .font(distance < rowHeight / 2 ? FitTheme.display(27) : FitTheme.body(22))
                            .foregroundStyle(distance < rowHeight / 2 ? FitTheme.orange : .white.opacity(0.4))
                            .frame(maxWidth: .infinity).frame(height: rowHeight)
                            .offset(y: CGFloat(delta) * rowHeight + dragOffset)
                            .onTapGesture { age = value }
                    }
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
            .contentShape(Rectangle())
            .clipped()
            .mask { LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom) }
            .gesture(DragGesture(minimumDistance: 3)
                .updating($dragOffset) { value, state, _ in state = value.translation.height }
                .onEnded { value in
                    let change = Int((-value.translation.height / rowHeight).rounded())
                    age = min(100, max(13, age + change))
                    UISelectionFeedbackGenerator().selectionChanged()
                })
        }
        .fitSurface(radius: 23)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your age")
        .accessibilityValue("\(age) years")
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

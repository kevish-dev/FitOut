import SwiftUI

enum FitTheme {
    static let orange = Color(red: 1, green: 0.27, blue: 0.015)
    static let background = Color(red: 0.018, green: 0.018, blue: 0.018)
    static let border = Color.white.opacity(0.19)
    static func display(_ size: CGFloat) -> Font { .custom("Orbitron-ExtraBold", size: size, relativeTo: .title) }
    static func label(_ size: CGFloat) -> Font { .custom("Orbitron-Bold", size: size, relativeTo: .headline) }
    static func body(_ size: CGFloat) -> Font { .custom("Rajdhani-Medium", size: size, relativeTo: .body) }
}

struct Surface: ViewModifier {
    var selected = false
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(selected ? FitTheme.orange.opacity(0.07) : Color.white.opacity(0.025))
                    .overlay {
                        if selected {
                            RadialGradient(colors: [FitTheme.orange.opacity(0.12), .clear], center: .bottomLeading, startRadius: 0, endRadius: 220)
                                .clipShape(RoundedRectangle(cornerRadius: radius))
                        }
                    }
            }
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(selected ? FitTheme.orange : FitTheme.border, lineWidth: selected ? 1.4 : 1) }
    }
}

extension View {
    func fitSurface(selected: Bool = false, radius: CGFloat = 16) -> some View {
        modifier(Surface(selected: selected, radius: radius))
    }
}

struct ScreenHeading: View {
    let first: String
    let accent: String
    var size: CGFloat = 29
    var body: some View {
        VStack(spacing: 2) {
            Text(first).foregroundStyle(.white)
            Text(accent).foregroundStyle(FitTheme.orange)
        }
        .font(FitTheme.display(size))
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct StepProgress: View {
    let step: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...4, id: \.self) { index in
                Capsule().fill(index <= step ? FitTheme.orange : Color.white.opacity(0.13))
                    .frame(width: 23, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup step \(step) of 4")
    }
}

struct BackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 55, height: 55)
                .fitSurface(radius: 30)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityIdentifier("backButton")
    }
}

struct NextButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("Next").font(.system(size: 18, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 20))
            }
            .frame(width: 132, height: 55)
            .background(Color.white.opacity(0.035), in: Capsule())
            .fitSurface(radius: 30)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nextButton")
    }
}

struct SlideToFinish: View {
    let enabled: Bool
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func finish() {
        guard enabled, !finished else { return }
        finished = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        action()
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 58)
            ZStack(alignment: .leading) {
                Capsule().fill(FitTheme.orange.opacity(0.08))
                Capsule().stroke(FitTheme.orange.opacity(enabled ? 0.8 : 0.25), lineWidth: 1.5)
                Text("Slide to Create My Journey")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.leading, 64).padding(.trailing, 12)
                    .opacity(1 - Double(offset / travel))
                Circle()
                    .fill(FitTheme.orange)
                    .overlay { Circle().stroke(.white.opacity(0.13), lineWidth: 1) }
                    .overlay { Image(systemName: "arrow.right").font(.system(size: 23, weight: .medium)) }
                    .frame(width: 54, height: 54)
                    .shadow(color: FitTheme.orange.opacity(0.25), radius: 14)
                    .offset(x: offset + 2)
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            guard enabled else { return }
                            offset = min(max(0, value.translation.width), travel)
                        }
                        .onEnded { _ in
                            if enabled && offset >= travel * 0.82 {
                                finish()
                            } else {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { offset = 0 }
                            }
                        })
            }
            .opacity(enabled ? 1 : 0.45)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Create my journey")
            .accessibilityHint(enabled ? "Double tap to save your profile" : "Select at least one fitness goal first")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { finish() }
            .accessibilityIdentifier("createJourneySlider")
        }
        .frame(height: 58)
    }
}

struct AvatarView: View {
    let profile: FitnessProfile
    var size: CGFloat = 108
    var placeholder = false
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.015))
            if profile.usesPhoto, let data = profile.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
            } else if placeholder {
                Image(systemName: "person.fill").font(.system(size: size * 0.48)).foregroundStyle(FitTheme.orange)
            } else {
                Text(profile.emoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().stroke(FitTheme.orange, lineWidth: 1.5) }
        .accessibilityLabel("Profile avatar")
    }
}

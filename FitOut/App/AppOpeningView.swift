import SwiftUI

/// A single, bounded brand moment. The system launch screen itself stays static.
struct AppOpeningView: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: CGFloat = 0
    @State private var settled = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(300, geometry.size.width * 0.76, geometry.size.height * 0.44)
            VStack(spacing: 0) {
                ZStack {
                    logo(side: side).opacity(reduceMotion ? 1 : 0.12)
                    if !reduceMotion {
                        logo(side: side)
                            .mask { LogoReveal(progress: reveal) }
                    }
                }
                .scaleEffect(reduceMotion || settled ? 1 : 0.94)
                // The source image has generous padding around the actual mark.
                .padding(.bottom, -side * 0.15)

                Text("FitOut")
                    .font(FitTheme.label(20))
                    .foregroundStyle(.white)
                    .opacity(reduceMotion || settled ? 1 : 0)
                    .padding(.horizontal, FitTheme.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color("LaunchBackground").ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture(perform: onComplete)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FitOut")
        .accessibilityValue("Opening app")
        .accessibilityAction(named: "Skip opening", onComplete)
        .accessibilityAction(.escape, onComplete)
        .task(id: reduceMotion) {
            do {
                if reduceMotion {
                    // No sweep or scaling, and no artificial one-second wait.
                    try await Task.sleep(for: .milliseconds(150))
                } else {
                    // Give SwiftUI one frame to install the mask's initial state.
                    try await Task.sleep(for: .milliseconds(30))
                    withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.68)) {
                        reveal = 1
                        settled = true
                    }
                    try await Task.sleep(for: .milliseconds(820))
                }
                try Task.checkCancellation()
                onComplete()
            } catch {
                // Removal/backgrounding cancels the task; it cannot navigate later.
            }
        }
    }

    private func logo(side: CGFloat) -> some View {
        Image("FitOutLogo")
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            // Fade only the source image's dark outer padding, preserving the FO mark.
            .mask {
                RadialGradient(colors: [.white, .white, .clear], center: .center,
                               startRadius: side * 0.39, endRadius: side * 0.54)
            }
            .accessibilityHidden(true)
    }
}

/// The slanted leading edge follows the angle of the F, revealing F then O.
private struct LogoReveal: Shape {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let slant = rect.width * 0.22
        let edge = -slant + (rect.width + slant * 2) * progress
        return Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: edge + slant, y: 0))
            path.addLine(to: CGPoint(x: edge, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}

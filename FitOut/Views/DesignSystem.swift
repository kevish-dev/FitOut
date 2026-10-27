import SwiftUI
import UIKit

enum FitTheme {
    static let pageInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 16
    static let cardInset: CGFloat = 16
    static let orange = adaptive(light: (0.73, 0.23, 0), dark: (1, 0.27, 0.015))
    static let background = adaptive(light: (0.96, 0.96, 0.97), dark: (0.018, 0.018, 0.018))
    static let textPrimary = Color(uiColor: .label)
    static let border = textPrimary.opacity(0.19)
    // Neutral backgrounds and surfaces; orange is reserved for foreground actions.
    static let dashboardAccent = adaptive(light: (0.73, 0.23, 0), dark: (1, 77.0 / 255, 0))
    static let dashboardBackground = adaptive(light: (0.95, 0.95, 0.96), dark: (11.0 / 255, 11.0 / 255, 13.0 / 255))
    static let surface = adaptive(light: (1, 1, 1), dark: (21.0 / 255, 21.0 / 255, 24.0 / 255))
    static let elevated = adaptive(light: (0.90, 0.90, 0.92), dark: (34.0 / 255, 34.0 / 255, 38.0 / 255))
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let subtleBorder = Color(uiColor: .separator)
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
    // The reference uses broad, geometric headlines and compact, clean UI copy.
    // Keep the sizes centralized so every screen follows the same hierarchy.
    static func hero(_ size: CGFloat = 36) -> Font { .custom("Orbitron-ExtraBold", size: size, relativeTo: .largeTitle) }
    static func display(_ size: CGFloat) -> Font { .custom("Orbitron-ExtraBold", size: size, relativeTo: .title) }
    static func label(_ size: CGFloat) -> Font { .custom("Orbitron-Bold", size: size, relativeTo: .headline) }
    static func metric(_ size: CGFloat) -> Font { .custom("Orbitron-Bold", size: size, relativeTo: .title) }
    static func section(_ size: CGFloat = 18) -> Font { .custom("Inter-SemiBold", size: size, relativeTo: .headline) }
    static func button(_ size: CGFloat = 16) -> Font { .custom("Inter-SemiBold", size: size, relativeTo: .body) }
    static func body(_ size: CGFloat = 16) -> Font { .custom("Inter-Regular", size: size, relativeTo: .body) }
    static func medium(_ size: CGFloat = 13) -> Font { .custom("Inter-Medium", size: size, relativeTo: .subheadline) }
    static func strong(_ size: CGFloat = 16) -> Font { .custom("Inter-Bold", size: size, relativeTo: .body) }
}

/// Short, event-driven feedback only; no idle loops or page entrance choreography.
enum FitMotion {
    static func change(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.18) }
    static func press(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeOut(duration: 0.12) }
}

/// Plain appearance with the entire laid-out label participating in hit testing.
/// Keep sizing/padding inside the label so visible controls have matching targets.
/// Delegating to the native primitive preserves disabled, keyboard, repeat and
/// accessibility behavior instead of adding a competing tap gesture.
struct FitPlainButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == FitPlainButtonStyle {
    static var fitPlain: FitPlainButtonStyle { FitPlainButtonStyle() }
}

extension Binding {
    /// Collection offsets can go stale while SwiftUI removes/reorders a focused
    /// row. Resolve identity on every access and ignore writes to removed rows.
    func identifiedElement<Element: Identifiable & Sendable>(id: Element.ID, fallback: Element) -> Binding<Element> where Value == [Element], Element.ID: Sendable {
        Binding<Element>(get: { wrappedValue.first { $0.id == id } ?? fallback }, set: { value in
            guard value.id == id, let index = wrappedValue.firstIndex(where: { $0.id == id }) else { return }
            var values = wrappedValue; values[index] = value; wrappedValue = values
        })
    }
}

struct Surface: ViewModifier {
    var selected = false
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius)
                    .fill(FitTheme.textPrimary.opacity(selected ? 0.055 : 0.025))
            }
            .overlay { RoundedRectangle(cornerRadius: radius).stroke(selected ? FitTheme.orange : FitTheme.border, lineWidth: selected ? 1.4 : 1) }
    }
}

extension View {
    func dashboardGlass<S: Shape>(in shape: S, highlighted: Bool = false, interactive: Bool = false) -> some View {
        modifier(DashboardGlass(shape: shape, highlighted: highlighted, interactive: interactive))
    }

    func fitSurface(selected: Bool = false, radius: CGFloat = 16) -> some View {
        modifier(Surface(selected: selected, radius: radius))
    }
}

/// Home and Gym share one viewport, hero clearance, and vertical scroll behavior.
struct DashboardScroll<Header: View, Content: View, Backdrop: View>: View {
    @Environment(\.appNavigationStyle) private var navigationStyle
    private let header: Header
    private let content: Content
    private let backdrop: Backdrop
    private let onRefresh: @MainActor () async -> Void

    init(onRefresh: @escaping @MainActor () async -> Void,
         @ViewBuilder header: () -> Header,
         @ViewBuilder content: () -> Content,
         @ViewBuilder backdrop: () -> Backdrop) {
        self.onRefresh = onRefresh
        self.header = header()
        self.content = content()
        self.backdrop = backdrop()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                    header
                        .padding(.leading, FitTheme.pageInset)
                        .padding(.trailing, FitTheme.pageInset + (navigationStyle == .topRight ? 68 : 0))
                        .padding(.top, 16)
                    Color.clear
                        .frame(height: min(480, max(340, geometry.size.height * 0.56)))
                        .accessibilityHidden(true)
                    content
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await onRefresh() }
            .background { backdrop }
        }
    }
}

private struct DashboardGlass<S: Shape>: ViewModifier {
    let shape: S
    let highlighted: Bool
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(FitTheme.elevated, in: shape)
                .overlay { shape.stroke(FitTheme.textPrimary.opacity(highlighted ? 0.28 : 0.18), lineWidth: 1) }
        } else if #available(iOS 26.0, *) {
            // Native glass owns its edge; an overlay stroke would stay rigid during interaction.
            content.glassEffect(
                .regular.interactive(interactive),
                in: shape
            )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(FitTheme.surface.opacity(0.5), in: shape)
                .overlay {
                    shape.stroke(
                        LinearGradient(colors: [FitTheme.textPrimary.opacity(highlighted ? 0.38 : 0.24), FitTheme.textPrimary.opacity(0.05), FitTheme.textPrimary.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                }
        }
    }
}

struct ScreenHeading: View {
    let first: String
    let accent: String
    var size: CGFloat = 29
    var body: some View {
        VStack(spacing: 2) {
            Text(first).foregroundStyle(FitTheme.textPrimary)
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
    var totalSteps = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...totalSteps, id: \.self) { index in
                Capsule().fill(index <= step ? FitTheme.orange : FitTheme.textPrimary.opacity(0.13))
                    .frame(width: 23, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setup step \(step) of \(totalSteps)")
        .animation(FitMotion.change(reduceMotion: reduceMotion), value: step)
    }
}

struct BackButton: View {
    @Environment(\.fitHaptics) private var haptics
    let action: () -> Void
    var body: some View {
        Button { haptics?.play(.navigation); action() } label: {
            Image(systemName: "arrow.left")
                .font(.system(size: 22, weight: .medium))
                .frame(width: 55, height: 55)
                .fitSurface(radius: 30)
        }
        .buttonStyle(RoutineEditorPressStyle())
        .accessibilityLabel("Back")
        .accessibilityIdentifier("backButton")
    }
}

struct NextButton: View {
    @Environment(\.fitHaptics) private var haptics
    let action: () -> Void
    var body: some View {
        Button { haptics?.play(.navigation); action() } label: {
            HStack(spacing: 14) {
                Text("Next").font(FitTheme.button(18))
                Image(systemName: "arrow.right").font(.system(size: 20))
            }
            .frame(width: 132, height: 55)
            .background(FitTheme.textPrimary.opacity(0.035), in: Capsule())
            .fitSurface(radius: 30)
        }
        .buttonStyle(RoutineEditorPressStyle())
        .accessibilityIdentifier("nextButton")
    }
}

struct SlideToFinish: View {
    @Environment(\.fitHaptics) private var haptics
    let enabled: Bool
    let action: () -> Void
    @State private var offset: CGFloat = 0
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func finish() {
        guard enabled, !finished else { return }
        finished = true
        haptics?.play(.selection)
        action()
        // A failed persistence attempt must allow another slide after retry.
        finished = false
        offset = 0
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 58)
            ZStack(alignment: .leading) {
                Capsule().fill(FitTheme.orange.opacity(0.08))
                Capsule().stroke(FitTheme.orange.opacity(enabled ? 0.8 : 0.25), lineWidth: 1.5)
                Text("Slide to Create My Journey")
                    .font(FitTheme.medium(13))
                    .foregroundStyle(FitTheme.textPrimary.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.leading, 64).padding(.trailing, 12)
                    .opacity(1 - Double(offset / travel))
                Circle()
                    .fill(FitTheme.orange)
                    .overlay { Circle().stroke(FitTheme.textPrimary.opacity(0.13), lineWidth: 1) }
                    .overlay { Image(systemName: "arrow.right").font(.system(size: 23, weight: .medium)).foregroundStyle(.white) }
                    .frame(width: 54, height: 54)
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
            .accessibilityHint(enabled ? "Double tap to save your profile" : "Complete your profile and choose a primary fitness goal first")
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
            Circle().fill(FitTheme.textPrimary.opacity(0.015))
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

import SwiftUI
import UIKit

struct WorkoutStreakCelebrationView: View {
    let store: WorkoutStreakStore
    @Environment(\.fitHaptics) private var haptics
    let close: () -> Void
    @State private var revealed = false
    @State private var displayedCount: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let event = store.pending {
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 22) {
                        Color.clear.frame(height: typeSize.isAccessibilitySize ? 80 : min(220, viewport.size.height * 0.23))
                            .accessibilityHidden(true)
                        VStack(spacing: 18) {
                            Image(systemName: "flame.fill").font(.system(size: 68, weight: .regular))
                                .foregroundStyle(FitTheme.dashboardAccent)
                                .scaleEffect(revealed || reduceMotion ? 1 : 0.75)
                                .rotationEffect(.degrees(revealed || reduceMotion ? 0 : -8))
                                .accessibilityHidden(true)
                            Text("\(displayedCount ?? (reduceMotion ? event.snapshot.consecutiveDays : event.previousCount))").font(FitTheme.display(typeSize.isAccessibilitySize ? 100 : min(156, viewport.size.width * 0.38)))
                                .monospacedDigit().contentTransition(.numericText(countsDown: false))
                                .lineLimit(1).minimumScaleFactor(0.4)
                                .accessibilityLabel("\(event.snapshot.consecutiveDays) day streak")
                            Text("Day Streak").font(FitTheme.display(28)).foregroundStyle(FitTheme.dashboardAccent)
                            Text("Workout complete.\nOne more day of showing up.")
                                .font(FitTheme.body(17)).foregroundStyle(FitTheme.textSecondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        week(event)
                    }
                    .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
                .background(alignment: .top) {
                    Image("FitnessHero").resizable().scaledToFill()
                        .frame(width: viewport.size.width, height: min(550, viewport.size.height * 0.62), alignment: .top)
                        .clipped()
                        .mask { LinearGradient(stops: [.init(color: .black.opacity(0.7), location: 0), .init(color: .black.opacity(0.45), location: 0.45), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
                        .accessibilityHidden(true)
                }
                .background(FitTheme.dashboardBackground)
                .overlay(alignment: .topTrailing) {
                    Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44).dashboardGlass(in: Circle(), interactive: true) }
                        .buttonStyle(.plain).padding(.trailing, FitTheme.pageInset).padding(.top, 8)
                        .accessibilityLabel("Close streak celebration")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StreakContinueSlider(action: close).id(event.id)
                    .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
            }
            .foregroundStyle(FitTheme.textPrimary).background(FitTheme.dashboardBackground.ignoresSafeArea())
            .accessibilityIdentifier("workoutStreakCelebration")
            .accessibilityAction(.escape, close)
            .onChange(of: revealed) { _, value in if value { haptics?.play(.streak) } }
            .task(id: event.id) {
                displayedCount = reduceMotion ? event.snapshot.consecutiveDays : event.previousCount
                guard !reduceMotion else { revealed = true; return }
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                withAnimation(.spring(response: 0.65, dampingFraction: 0.8)) {
                    revealed = true; displayedCount = event.snapshot.consecutiveDays
                }
            }
        }
    }
    private func week(_ event: WorkoutStreakCelebration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(event.snapshot.weekDays.enumerated()), id: \.element.id) { index, day in
                let earnedToday = day.date == event.day
                VStack(spacing: 12) {
                    Text(day.date, format: .dateTime.weekday(.narrow)).font(FitTheme.medium(13)).foregroundStyle(FitTheme.textSecondary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(day.isCompleted ? FitTheme.dashboardAccent : FitTheme.textPrimary.opacity(0.045))
                        if day.isCompleted {
                            Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                                .scaleEffect(!earnedToday || revealed || reduceMotion ? 1 : 0.4)
                                .opacity(!earnedToday || revealed || reduceMotion ? 1 : 0)
                        } else if day.isRestDay {
                            Image(systemName: "moon.fill").font(.system(size: 17)).foregroundStyle(FitTheme.textSecondary)
                        }
                    }.frame(minHeight: 44)
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.05), value: revealed)
                }.frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)) + (day.isCompleted ? ", workout completed" : day.isRestDay ? ", planned rest day, streak protected" : ", no completed workout"))
            }
        }.padding(FitTheme.cardInset).dashboardGlass(in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct StreakContinueSlider: View {
    let action: () -> Void
    @GestureState private var drag: CGSize?
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fitHaptics) private var haptics

    var body: some View {
        GeometryReader { geometry in
            let travel = max(0, geometry.size.width - 76)
            let offset = finished ? travel : min(travel, max(0, drag?.width ?? 0))
            ZStack(alignment: .leading) {
                Text("Continue").font(FitTheme.button(19))
                    .frame(maxWidth: .infinity).padding(.leading, 86)
                    .opacity(travel > 0 ? 1 - Double(offset / travel) : 1)
                    .allowsHitTesting(false)
                Image(systemName: "arrow.right").font(.system(size: 23, weight: .medium))
                    .foregroundStyle(.white).frame(width: 68, height: 62)
                    .background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 18))
                    .contentShape(RoundedRectangle(cornerRadius: 18))
                    .offset(x: offset)
                    .gesture(DragGesture(minimumDistance: 3)
                        .updating($drag) { value, state, _ in
                            guard !finished else { return }
                            state = value.translation
                        }
                        .onEnded { value in
                            guard travel > 0, value.translation.width >= travel * 0.85 else { return }
                            finish()
                        })
            }
            // GestureState resets cancelled/short drags as well as completed ones.
            .animation(reduceMotion || drag != nil ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: offset)
            .padding(4).dashboardGlass(in: RoundedRectangle(cornerRadius: 22), interactive: true)
        }
        .frame(height: 70)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Continue")
        .accessibilityHint("Slide the arrow from left to right to continue, or double tap with VoiceOver.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { finish() }
        .accessibilityIdentifier("continueStreakCelebration")
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        haptics?.play(.selection)
        action()
    }
}

/// Presents over the current workout sheet, retaining its summary and Undo state.
/// No extra window is created and native presentation owns all touch interception.
@MainActor final class WorkoutStreakPresenter: NSObject {
    private let store: WorkoutStreakStore
    private let enabled: Bool
    private let preferences: () -> AppPreferences
    private let haptics: HapticService?
    private weak var controller: UIViewController?
    private var task: Task<Void, Never>?
    private var active = false
    init(store: WorkoutStreakStore, enabled: Bool, preferences: @escaping () -> AppPreferences, haptics: HapticService? = nil) {
        self.store = store; self.enabled = enabled; self.preferences = preferences; self.haptics = haptics
    }
    func sceneChanged(active: Bool) { self.active = active; refresh() }
    func refresh() {
        guard enabled else { return }
        guard store.pending != nil else {
            task?.cancel(); task = nil
            controller?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled); controller = nil
            return
        }
        guard active, controller == nil, task == nil else { return }
        task = Task { [weak self] in
            defer { self?.task = nil }
            // Let set completion, summary and confirmation dismissal settle first.
            for _ in 0..<8 {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self, self.active, self.store.pending != nil, !Task.isCancelled else { return }
                if self.present() { return }
            }
        }
    }
    private func present() -> Bool {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return false }
        var presenter = root
        while let next = presenter.presentedViewController { presenter = next }
        guard !(presenter is UIAlertController), !presenter.isBeingDismissed, !presenter.isBeingPresented,
              presenter.transitionCoordinator == nil, presenter.viewIfLoaded?.window != nil else { return false }
        let settings = preferences()
        let host = UIHostingController(rootView: WorkoutStreakCelebrationView(store: store) { [weak self] in self?.close() }
            .environment(\.fitHaptics, haptics)
            .preferredColorScheme(settings.appearance.colorScheme))
        host.modalPresentationStyle = .overFullScreen
        host.modalTransitionStyle = .crossDissolve
        host.view.backgroundColor = .clear; host.isModalInPresentation = true
        controller = host
        presenter.present(host, animated: !UIAccessibility.isReduceMotionEnabled)
        return true
    }
    private func close() {
        if let event = store.pending { store.acknowledge(event.id) }
        controller?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled); controller = nil
    }
}

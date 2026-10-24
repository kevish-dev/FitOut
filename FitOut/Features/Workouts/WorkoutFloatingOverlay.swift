import SwiftUI
import UIKit
import Observation
import Combine

/// One pass-through scene window keeps the workout reachable over navigation and sheets.
@MainActor @Observable final class WorkoutFloatingController {
    let store: WorkoutStore
    let gym: GymStore
    let profile: ProfileStore
    let defaults: UserDefaults
    var presentingWorkout = false
    private var window: WorkoutPassThroughWindow?
    private weak var previousKeyWindow: UIWindow?
    private var sceneActive = false
    private var appearance = UIUserInterfaceStyle.dark
    func setAppearance(_ scheme: ColorScheme?) {
        appearance = scheme.map { $0 == .dark ? .dark : .light } ?? .unspecified
        window?.overrideUserInterfaceStyle = appearance
    }
    init(store: WorkoutStore, gym: GymStore, profile: ProfileStore, defaults: UserDefaults) {
        self.store = store; self.gym = gym; self.profile = profile; self.defaults = defaults
    }
    func sceneChanged(active: Bool) { sceneActive = active; refresh() }
    func refresh() {
        guard sceneActive, profile.draft.completedAt != nil, store.active != nil || presentingWorkout else { window?.isHidden = true; return }
        if window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) {
            let overlay = WorkoutPassThroughWindow(windowScene: scene)
            overlay.backgroundColor = .clear; overlay.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
            overlay.overrideUserInterfaceStyle = appearance
            let root = UIHostingController(rootView: WorkoutFloatingRoot(controller: self))
            root.view.backgroundColor = .clear; overlay.rootViewController = root
            window = overlay
        }
        window?.isHidden = false
    }
    func open() {
        guard store.active != nil, !presentingWorkout else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        previousKeyWindow = window?.windowScene?.windows.first { $0.isKeyWindow && $0 !== window }
        window?.presentsEditor = true; window?.makeKey()
        presentingWorkout = true
    }
    func closed() {
        presentingWorkout = false; window?.presentsEditor = false
        previousKeyWindow?.makeKey(); previousKeyWindow = nil
        refresh()
    }
    func setFrame(_ frame: CGRect) { window?.controlFrame = frame }
}

private final class WorkoutPassThroughWindow: UIWindow {
    var controlFrame = CGRect.zero
    var presentsEditor = false
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard presentsEditor || controlFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}
private struct WorkoutFloatingFrame: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
private struct WorkoutFloatingRoot: View {
    @Bindable var controller: WorkoutFloatingController
    @State private var vertical = 0.73
    @State private var rightSide = true
    @GestureState private var drag = CGSize.zero
    @State private var keyboardTop: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var visible: Bool { controller.store.active != nil && controller.store.visibleEditorCount == 0 && !controller.presentingWorkout }
    var body: some View {
        GeometryReader { geometry in
            if visible, let session = controller.store.active {
                let width = min(210.0, geometry.size.width - 40)
                let top = max(150, geometry.safeAreaInsets.top + 96)
                let bottom = max(top, min(geometry.size.height - geometry.safeAreaInsets.bottom - 110, keyboardTop.map { $0 - 44 } ?? geometry.size.height))
                let baseY = top + (bottom - top) * vertical
                let baseX = rightSide ? geometry.size.width - width / 2 - 20 : width / 2 + 20
                let centerY = min(bottom, max(top, baseY + drag.height))
                let centerX = baseX + drag.width
                FloatingWorkoutPill(session: session, store: controller.store, open: controller.open)
                    .frame(width: width)
                    .background {
                        GeometryReader { proxy in Color.clear.preference(key: WorkoutFloatingFrame.self, value: proxy.frame(in: .named("workout-overlay"))) }
                    }
                    .position(x: min(geometry.size.width - width / 2 - 12, max(width / 2 + 12, centerX)), y: centerY)
                    .simultaneousGesture(DragGesture(minimumDistance: 12)
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                rightSide = baseX + value.translation.width > geometry.size.width / 2
                                vertical = min(1, max(0, (baseY + value.translation.height - top) / max(1, bottom - top)))
                            }
                        })
            }
        }
        .coordinateSpace(name: "workout-overlay").ignoresSafeArea()
        .onPreferenceChange(WorkoutFloatingFrame.self) { controller.setFrame($0) }
        .onChange(of: visible) { _, value in if !value { controller.setFrame(.zero) } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardTop = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.minY
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardTop = nil }
        .sheet(isPresented: $controller.presentingWorkout, onDismiss: controller.closed) {
            NavigationStack {
                ActiveWorkoutView(store: controller.store, gym: controller.gym, unit: controller.profile.draft.weightUnit, defaults: controller.defaults)
            }
        }
    }
}

private struct FloatingWorkoutPill: View {
    let session: WorkoutSession
    let store: WorkoutStore
    let open: () -> Void
    var body: some View {
        HStack(spacing: 2) {
            Button(action: open) {
                HStack(spacing: 9) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 17)).foregroundStyle(FitTheme.dashboardAccent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.status == .paused ? "Paused workout" : "Workout running").font(FitTheme.medium(10)).foregroundStyle(FitTheme.textSecondary)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(WorkoutDisplay.clock(session.duration(at: context.date))).font(FitTheme.strong(17)).monospacedDigit()
                        }
                    }
                }.frame(maxWidth: .infinity, minHeight: 56)
            }.buttonStyle(.plain).accessibilityLabel("Open current workout").accessibilityHint("Drag this control to move it")
            Button { if session.status == .paused { store.resume() } else { store.pause() } } label: {
                Image(systemName: session.status == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .medium)).frame(width: 44, height: 52)
            }.buttonStyle(.plain).accessibilityLabel(session.status == .paused ? "Resume workout" : "Pause workout")
        }
        .padding(.leading, 14).padding(.trailing, 4).foregroundStyle(FitTheme.textPrimary)
        .dashboardGlass(in: Capsule(), highlighted: true, interactive: true)
        .shadow(color: .black.opacity(0.25), radius: 16, y: 5)
        .accessibilityAction(named: Text("End rest")) { if session.restUntil != nil { store.endRest() } }
    }
}

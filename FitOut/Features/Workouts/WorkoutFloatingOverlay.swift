import SwiftUI
import UIKit
import Observation

/// One small view in the app's own window: native glass samples the real page,
/// and only the visible control's bounds can intercept touches.
@MainActor @Observable final class WorkoutFloatingController: NSObject, UIAdaptivePresentationControllerDelegate {
    let store: WorkoutStore
    let gym: GymStore
    let profile: ProfileStore
    let defaults: UserDefaults
    private let haptics: HapticService?
    private(set) var presentingWorkout = false
    private weak var window: UIWindow?
    private weak var nativeTabBar: UITabBar?
    private weak var presentedEditor: UIViewController?
    private var control: FloatingControlContainer?
    private var sceneActive = false
    private var appearance = UIUserInterfaceStyle.dark
    private var keyboardFrame: CGRect?
    private var obstructions: [String: CGRect] = [:]
    private var dockRight = true
    private var vertical: CGFloat = 0.68
    private var dragStart = CGPoint.zero
    private var dragging = false
    private var positioning = false

    init(store: WorkoutStore, gym: GymStore, profile: ProfileStore, defaults: UserDefaults, haptics: HapticService? = nil) {
        self.store = store; self.gym = gym; self.profile = profile; self.defaults = defaults; self.haptics = haptics
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardHidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    func setAppearance(_ scheme: ColorScheme?) {
        appearance = scheme.map { $0 == .dark ? .dark : .light } ?? .unspecified
        control?.overrideUserInterfaceStyle = appearance
        presentedEditor?.overrideUserInterfaceStyle = appearance
        refresh()
    }
    func sceneChanged(active: Bool) { sceneActive = active; refresh() }
    func protect(_ id: String, frame: CGRect?) {
        guard obstructions[id] != frame else { return }
        obstructions[id] = frame
        if !dragging { layout() }
    }
    func refresh() {
        guard sceneActive, profile.draft.completedAt != nil, store.active != nil,
              store.visibleEditorCount == 0, !presentingWorkout else { control?.isHidden = true; return }
        guard let appWindow = appWindow() else { return }
        if window !== appWindow || control == nil {
            control?.removeFromSuperview(); window = appWindow; nativeTabBar = nil
            let content = UIHostingConfiguration {
                FloatingWorkoutPill(store: self.store, open: { [weak self] in _ = self?.open() },
                    move: { [weak self] delta in self?.move(delta) })
            }.margins(.all, 0).makeContentView()
            content.backgroundColor = .clear
            let view = FloatingControlContainer(content: content)
            view.overrideUserInterfaceStyle = appearance
            view.geometryChanged = { [weak self] in if self?.dragging != true { self?.layout() } }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panChanged(_:)))
            pan.cancelsTouchesInView = true; pan.delaysTouchesBegan = false
            view.addGestureRecognizer(pan)
            appWindow.addSubview(view); control = view
        }
        if let control { appWindow.bringSubviewToFront(control) }
        layout()
    }
    @discardableResult func open() -> Bool {
        if presentingWorkout { return true }
        guard store.active != nil, let window = appWindow(), let root = window.rootViewController else { return false }
        let presenter = topController(root)
        guard !presenter.isBeingDismissed, presenter.viewIfLoaded?.window != nil else { return false }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let editor = UIHostingController(rootView: NavigationStack {
            ActiveWorkoutView(store: store, gym: gym, unit: profile.draft.weightUnit, defaults: defaults,
                onMinimize: { [weak self] in self?.closeEditor() }).environment(\.fitHaptics, haptics)
        })
        editor.overrideUserInterfaceStyle = appearance
        editor.modalPresentationStyle = .pageSheet
        editor.sheetPresentationController?.detents = [.large()]
        editor.sheetPresentationController?.prefersGrabberVisible = true
        editor.presentationController?.delegate = self
        presentingWorkout = true; control?.isHidden = true; presentedEditor = editor
        presenter.present(editor, animated: !UIAccessibility.isReduceMotionEnabled)
        return true
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { closed() }
    private func closeEditor() {
        guard let presentedEditor else { closed(); return }
        presentedEditor.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in self?.closed() }
    }
    private func closed() { presentedEditor = nil; presentingWorkout = false; refresh() }
    private func appWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
        let windows = scenes.flatMap(\.windows).filter { !$0.isHidden && $0.windowLevel == .normal && $0.rootViewController != nil }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
    private func topController(_ root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController, !presented.isBeingDismissed { return topController(presented) }
        if let navigation = root as? UINavigationController, let visible = navigation.visibleViewController { return topController(visible) }
        if let tabs = root as? UITabBarController, let selected = tabs.selectedViewController { return topController(selected) }
        return root
    }
    private func findTabBar(_ root: UIViewController) -> UITabBar? {
        if let tabs = root as? UITabBarController { return tabs.tabBar }
        for child in root.children { if let bar = findTabBar(child) { return bar } }
        return nil
    }
    private func geometry() -> FloatingWorkoutGeometry? {
        guard let window, let control else { return nil }
        let width = min(238, window.bounds.width - 24)
        let fitting = control.content.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        let size = CGSize(width: width, height: max(60, ceil(fitting.height)))
        var blocks = Array(obstructions.values)
        if let keyboardFrame {
            let localKeyboard = window.screen.coordinateSpace.convert(keyboardFrame, to: window)
            if localKeyboard.intersects(window.bounds) { blocks.append(localKeyboard) }
        }
        if nativeTabBar == nil, let root = window.rootViewController { nativeTabBar = findTabBar(root) }
        if let bar = nativeTabBar, !bar.isHidden, bar.alpha > 0.01, bar.window === window { blocks.append(bar.convert(bar.bounds, to: window)) }
        return FloatingWorkoutGeometry(viewport: window.bounds, safeArea: window.safeAreaInsets, size: size, obstructions: blocks)
    }
    private func layout() {
        guard !positioning else { return }
        positioning = true
        defer { positioning = false }
        guard !dragging, sceneActive, store.active != nil, store.visibleEditorCount == 0, !presentingWorkout,
              profile.draft.completedAt != nil, let control, let geometry = geometry() else { return }
        guard let frame = geometry.frame(near: geometry.preferredCenter(right: dockRight, fraction: vertical)) else { control.isHidden = true; return }
        control.isHidden = false
        if control.frame != frame { control.frame = frame }
    }
    @objc private func panChanged(_ gesture: UIPanGestureRecognizer) {
        guard let window, let control, let geometry = geometry() else { return }
        switch gesture.state {
        case .began: dragging = true; dragStart = control.center
        case .changed:
            let delta = gesture.translation(in: window)
            if let frame = geometry.frame(near: CGPoint(x: dragStart.x + delta.x, y: dragStart.y + delta.y)) { control.frame = frame }
        case .ended, .cancelled:
            dragging = false; dockRight = control.center.x >= window.bounds.midX
            vertical = geometry.verticalFraction(for: control.center)
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.2) { self.layout() }
        default: break
        }
    }
    private func move(_ delta: CGFloat) {
        if delta == 0 { dockRight.toggle() } else { vertical = min(1, max(0, vertical + delta)) }
        layout()
    }
    @objc private func keyboardChanged(_ notification: Notification) {
        keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        layout()
    }
    @objc private func keyboardHidden(_ notification: Notification) { keyboardFrame = nil; layout() }
}

private final class FloatingControlContainer: UIView {
    let content: UIView
    var geometryChanged: (() -> Void)?
    init(content: UIView) {
        self.content = content; super.init(frame: .zero)
        backgroundColor = .clear; addSubview(content)
        content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: FloatingControlContainer, _) in view.geometryChanged?() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); content.frame = bounds; geometryChanged?() }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); geometryChanged?() }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isHidden && UIBezierPath(roundedRect: bounds, cornerRadius: min(bounds.width, bounds.height) / 2).contains(point)
    }
}

private struct FloatingWorkoutPill: View {
    let store: WorkoutStore
    let open: () -> Void
    let move: (CGFloat) -> Void
    var body: some View {
        if let session = store.active {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal").font(.system(size: 11)).rotationEffect(.degrees(90))
                    .foregroundStyle(FitTheme.textSecondary).frame(width: 18).accessibilityHidden(true)
                Button(action: open) {
                    HStack(spacing: 9) {
                        Image(systemName: "dumbbell.fill").font(.system(size: 16)).foregroundStyle(FitTheme.dashboardAccent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.status == .paused ? "Paused workout" : "Workout running").font(FitTheme.medium(10)).foregroundStyle(FitTheme.textSecondary).lineLimit(1)
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text(WorkoutDisplay.clock(session.duration(at: context.date))).font(FitTheme.strong(17)).monospacedDigit().lineLimit(1)
                            }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 56)
                }.buttonStyle(.plain).accessibilityLabel("Open current workout").accessibilityHint("Drag the handle to move this control")
                Button { if session.status == .paused { store.resume() } else { store.pause() } } label: {
                    Image(systemName: session.status == .paused ? "play.fill" : "pause.fill").font(.system(size: 15, weight: .medium)).frame(width: 44, height: 52)
                }.buttonStyle(.plain).accessibilityLabel(session.status == .paused ? "Resume workout" : "Pause workout")
            }
            .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 2).foregroundStyle(FitTheme.textPrimary)
            .dashboardGlass(in: Capsule(), interactive: true)
            .accessibilityElement(children: .contain).accessibilityIdentifier("floatingWorkoutControl")
            .accessibilityAction(named: Text("Move to other edge")) { move(0) }
            .accessibilityAction(named: Text("Move up")) { move(-0.15) }
            .accessibilityAction(named: Text("Move down")) { move(0.15) }
            .accessibilityAction(named: Text("End rest")) { if session.restUntil != nil { store.endRest() } }
        }
    }
}

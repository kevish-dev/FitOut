import SwiftUI
import UIKit

/// Reports actual UIKit window rectangles for pinned composers/action docks.
/// A nil ID only reports layout changes; it does not exclude the whole page.
struct WorkoutControlLayoutReader: UIViewRepresentable {
    var id: String? = nil
    func makeUIView(context: Context) -> ReportView { ReportView(id: id) }
    func updateUIView(_ view: ReportView, context: Context) { view.report() }
    static func dismantleUIView(_ view: ReportView, coordinator: ()) { view.clear() }
    final class ReportView: UIView {
        let key: String?
        init(id: String?) { key = id; super.init(frame: .zero); isUserInteractionEnabled = false; backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        func clear() { if let key { WorkoutRuntime.presentation?.protectWorkoutControl(key, frame: nil) } }
        func report() {
            guard let window, !bounds.isEmpty else { clear(); return }
            var ancestor: UIView? = self
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { clear(); return }
                ancestor = view.superview
            }
            if let key { WorkoutRuntime.presentation?.protectWorkoutControl(key, frame: convert(bounds, to: window)) }
            else { WorkoutRuntime.presentation?.overlayChanged() }
        }
    }
}

extension View {
    func workoutControlClearance(_ id: String) -> some View {
        background(WorkoutControlLayoutReader(id: id))
            .onDisappear { WorkoutRuntime.presentation?.protectWorkoutControl(id, frame: nil) }
    }
}

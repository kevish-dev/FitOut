import SwiftUI

/// Integer ticks avoid floating-point scroll identities; an off-grid current
/// value is kept exactly until the user deliberately scrolls or enters a value.
struct WorkoutWheelRange {
    let minimum: Double
    let maximum: Double
    let step: Double
    var count: Int { max(1, Int(((maximum - minimum) / step).rounded(.down)) + 1) }
    func number(at tick: Int) -> Double { ((minimum + Double(max(0, min(count - 1, tick))) * step) * 1000).rounded() / 1000 }
    func tick(for value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let bounded = min(maximum, max(minimum, value))
        return max(0, min(count - 1, Int(((bounded - minimum) / step).rounded())))
    }
    func adjusted(_ value: Double, direction: Int) -> Double {
        min(maximum, max(minimum, ((value + Double(direction) * step) * 1000).rounded() / 1000))
    }
}

struct WorkoutNumberWheel: View {
    let title: String
    @Binding var value: Double
    var integer = false
    var step = 1.0
    var minimum = 0.0
    var maximum = 1000.0
    var editingChanged: (Bool) -> Void = { _ in }
    @Environment(\.fitHaptics) private var haptics
    @ScaledMetric(relativeTo: .title2) private var rowHeight: CGFloat = 34
    @State private var selected: Int?
    @State private var scrolling = false
    @State private var exact = false
    private var range: WorkoutWheelRange { .init(minimum: minimum, maximum: maximum, step: step) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary)
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(FitTheme.dashboardAccent.opacity(0.07)).frame(height: rowHeight + 10)
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<range.count, id: \.self) { tick in
                                let focused = tick == selected
                                // Do not round a recalled 43.27 kg to a nearby wheel tick on load.
                                let displayed = focused && !scrolling ? value : range.number(at: tick)
                                Text(displayed.formatted(.number.precision(.fractionLength(0...(integer ? 0 : 2)))))
                                    .font(focused ? FitTheme.metric(27) : FitTheme.body(21))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .monospacedDigit().foregroundStyle(focused ? FitTheme.dashboardAccent : FitTheme.textSecondary.opacity(0.7))
                                    .frame(maxWidth: .infinity).frame(height: rowHeight).id(tick)
                            }
                        }.scrollTargetLayout()
                    }
                    .safeAreaPadding(.vertical, max(0, (geometry.size.height - rowHeight) / 2))
                    .scrollIndicators(.hidden).scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $selected, anchor: .center)
                    .onScrollPhaseChange { _, phase in
                        if phase == .interacting || phase == .decelerating {
                            if !scrolling { scrolling = true; editingChanged(true) }
                        } else if phase == .idle, scrolling {
                            commit(); scrolling = false; editingChanged(false)
                        }
                    }
                    .onAppear { selected = range.tick(for: value) }
                    .onChange(of: value) { _, new in if !scrolling { selected = range.tick(for: new) } }
                    HStack { Capsule().fill(FitTheme.dashboardAccent).frame(width: 2); Spacer(); Capsule().fill(FitTheme.dashboardAccent).frame(width: 2) }
                        .frame(height: rowHeight + 6).allowsHitTesting(false)
                }
                .clipped().mask { LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom) }
            }
            .frame(height: min(rowHeight * 3.8, 210))
            .fitSurface(radius: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(value.formatted(.number.precision(.fractionLength(0...(integer ? 0 : 2)))))
            .accessibilityHint("Swipe up or down to adjust. Use Enter exact value for typing.")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 1 : -1
                value = range.adjusted(value, direction: delta); haptics?.play(.selection)
            }
            Button { exact = true; editingChanged(true) } label: {
                Label("Enter exact", systemImage: "number").font(FitTheme.medium(12)).frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.plain).disabled(scrolling).accessibilityLabel("Enter exact \(title)")
        }
        .frame(minWidth: 108, maxWidth: .infinity)
        .onDisappear { if scrolling { commit(); scrolling = false; editingChanged(false) } }
        .sheet(isPresented: $exact, onDismiss: { editingChanged(false) }) {
            WorkoutExactNumber(title: title, value: $value, minimum: minimum, maximum: maximum, integer: integer)
                .presentationDetents([.medium])
        }
    }
    private func commit() {
        guard let selected else { return }
        let next = range.number(at: selected)
        if value != next { value = next; haptics?.play(.selection) }
    }
}

private struct WorkoutExactNumber: View {
    let title: String
    @Binding var value: Double
    let minimum: Double
    let maximum: Double
    let integer: Bool
    @State private var text = ""
    @FocusState private var focus: Bool
    @Environment(\.dismiss) private var dismiss
    private var number: Double? {
        guard let parsed = WorkoutConfigurationValue.parse(text, maximum: maximum, integer: integer, positive: false), parsed >= minimum else { return nil }
        return parsed
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField(title, text: $text).keyboardType(integer ? .numberPad : .decimalPad).focused($focus)
                    .font(FitTheme.metric(26)).accessibilityLabel(title)
                Text("\(minimum.formatted())–\(maximum.formatted())\(integer ? "; whole numbers" : "")").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                if !text.isEmpty && number == nil { Text("Enter a valid value in this range.").font(FitTheme.body(13)).foregroundStyle(.red) }
            }.nutritionForm().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if let number { value = number; dismiss() } }.disabled(number == nil) }
                }
                .onAppear { text = value.formatted(.number.grouping(.never).precision(.fractionLength(0...4))); focus = true }
        }
    }
}

import SwiftUI

struct WeightScreen: View {
    @Binding var profile: FitnessProfile
    var scale: CGFloat = 1
    var targetEnabled = true
    var onEnableTarget: (() -> Void)? = nil
    @State private var isTarget = false
    @State private var previewKG: Double?

    private var weight: Binding<Double> {
        let target = isTarget
        return Binding(get: { target ? profile.targetWeightKG : profile.currentWeightKG }, set: {
            if target { profile.targetWeightKG = $0 } else { profile.currentWeightKG = $0 }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "What’s your", accent: isTarget ? "target weight?" : "current weight?", size: 28 * scale)
                .padding(.bottom, 20 * scale)
            HStack(spacing: 0) {
                weightTab("CURRENT", target: false)
                weightTab("TARGET", target: true)
            }
            .fitSurface(radius: 13)
            .frame(maxWidth: 258 * scale)
            .padding(.bottom, 28 * scale)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.unit.display(previewKG ?? weight.wrappedValue), format: .number.precision(.fractionLength(0...1)))
                    .font(FitTheme.display(44 * scale))
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(profile.unit.rawValue).font(FitTheme.medium(19)).foregroundStyle(FitTheme.textPrimary.opacity(0.4))
            }
            .padding(FitTheme.cardInset)
            .frame(width: 190 * scale, height: 163 * scale)
            .fitSurface(radius: 14)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("weightValue")
            .padding(.bottom, 30 * scale)
            WeightRuler(kilograms: weight, unit: profile.unit, onPreview: { previewKG = $0 })
                .id("\(isTarget)-\(profile.unit.rawValue)")
                .frame(height: 88 * scale)
                .padding(.bottom, 20 * scale)
            HStack(spacing: 0) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Button {
                        profile.unit = unit
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(unit.rawValue)
                            .font(FitTheme.button(17))
                            .foregroundStyle(unit == profile.unit ? FitTheme.orange : FitTheme.textPrimary.opacity(0.8))
                            .frame(maxWidth: .infinity).frame(height: 42)
                            .fitSurface(selected: unit == profile.unit, radius: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(unit == .kg ? "Kilograms" : "Pounds")
                    .accessibilityAddTraits(unit == profile.unit ? .isSelected : [])
                }
            }
            .fitSurface(radius: 12)
            .frame(width: 156 * scale)
        }
        .onChange(of: targetEnabled) { _, enabled in if !enabled { isTarget = false } }
        .onChange(of: isTarget) { _, _ in previewKG = nil }
        .onChange(of: profile.unit) { _, _ in previewKG = nil }
    }

    private func weightTab(_ title: String, target: Bool) -> some View {
        Button {
            if target && !targetEnabled { onEnableTarget?() }
            isTarget = target
        } label: {
            Text(title).font(FitTheme.section(18))
                .foregroundStyle(isTarget == target ? FitTheme.orange : FitTheme.textPrimary.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: 38)
                .fitSurface(selected: isTarget == target, radius: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target ? "Target weight" : "Current weight")
        .accessibilityAddTraits(isTarget == target ? .isSelected : [])
    }
}

struct WeightRuler: View {
    @Binding var kilograms: Double
    let unit: WeightUnit
    var onPreview: ((Double) -> Void)? = nil
    @State private var selectedTick: Int?
    @State private var isScrolling = false
    private let tickWidth: CGFloat = 10

    private var ticks: ClosedRange<Int> { unit.range.lowerBound * 5 ... unit.range.upperBound * 5 }

    private func tick(for kilograms: Double) -> Int {
        min(ticks.upperBound, max(ticks.lowerBound, Int((unit.display(kilograms) * 5).rounded())))
    }

    private func commitSelection(updatePreview: Bool = true) {
        guard let selectedTick else { return }
        let value = min(250, max(25, unit.kilograms(Double(selectedTick) / 5)))
        if abs(kilograms - value) > 0.00001 { kilograms = value }
        if updatePreview { onPreview?(value) }
    }

    private func setDisplayedWeight(_ value: Double) {
        let bounded = min(Double(unit.range.upperBound), max(Double(unit.range.lowerBound), value))
        let snapped = (bounded * 5).rounded() / 5
        kilograms = min(250, max(25, unit.kilograms(snapped)))
        selectedTick = tick(for: kilograms)
        onPreview?(kilograms)
    }

    var body: some View {
        let displayed = selectedTick.map { Double($0) / 5 } ?? unit.display(kilograms)
        let accent = FitTheme.orange
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(ticks, id: \.self) { tick in
                        let major = tick.isMultiple(of: 5)
                        let selected = selectedTick == tick
                        Color.clear
                            .frame(width: tickWidth, height: 88)
                            .overlay(alignment: .top) {
                                if major {
                                    Text("\(tick / 5)")
                                        .font(selected ? FitTheme.strong(12) : FitTheme.medium(12))
                                        .foregroundStyle(selected ? accent : FitTheme.textPrimary.opacity(0.7))
                                        .fixedSize().offset(y: 1)
                                }
                            }
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(FitTheme.textPrimary.opacity(major ? 0.65 : 0.4))
                                    .frame(width: major ? 1.3 : 1, height: major ? 48 : 25)
                                    .offset(y: major ? 24 : 37)
                            }
                            .id(tick)
                    }
                }
                .scrollTargetLayout()
            }
            .safeAreaPadding(.horizontal, max(0, (geometry.size.width - tickWidth) / 2))
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selectedTick, anchor: .center)
            .onAppear { selectedTick = tick(for: kilograms) }
            .onChange(of: selectedTick) { _, tick in
                if isScrolling, let tick { onPreview?(min(250, max(25, unit.kilograms(Double(tick) / 5)))) }
            }
            .onChange(of: kilograms) { _, value in
                if !isScrolling { selectedTick = tick(for: value) }
            }
            .onScrollPhaseChange { _, phase in
                isScrolling = phase != .idle
                if phase == .idle {
                    commitSelection()
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onDisappear { if isScrolling { commitSelection(updatePreview: false) } }
        }
        .mask { LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .leading, endPoint: .trailing) }
        .overlay(alignment: .top) {
            VStack(spacing: 5) {
                Capsule().fill(accent).frame(width: 2, height: 48)
                Image(systemName: "triangle.fill").font(.system(size: 11)).foregroundStyle(accent)
            }.padding(.top, 24).allowsHitTesting(false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight ruler")
        .accessibilityValue("\(displayed.formatted(.number.precision(.fractionLength(0...1)))) \(unit.rawValue)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setDisplayedWeight(displayed + 0.2)
            case .decrement: setDisplayedWeight(displayed - 0.2)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("weightRuler")
    }
}

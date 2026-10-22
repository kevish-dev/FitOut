import SwiftUI

struct WeightScreen: View {
    @Binding var profile: FitnessProfile
    var scale: CGFloat = 1
    @State private var isTarget = false

    private var weight: Binding<Double> {
        Binding(get: { isTarget ? profile.targetWeightKG : profile.currentWeightKG }, set: {
            if isTarget { profile.targetWeightKG = $0 } else { profile.currentWeightKG = $0 }
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
                Text(profile.unit.display(weight.wrappedValue), format: .number.precision(.fractionLength(0...1)))
                    .font(FitTheme.display(44 * scale))
                    .contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(profile.unit.rawValue).font(.system(size: 19, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            }
            .padding(15)
            .frame(width: 190 * scale, height: 163 * scale)
            .fitSurface(radius: 14)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("weightValue")
            .padding(.bottom, 30 * scale)
            WeightRuler(kilograms: weight, unit: profile.unit)
                .id("\(isTarget)-\(profile.unit.rawValue)")
                .frame(height: 88 * scale)
                .padding(.horizontal, -12)
                .padding(.bottom, 20 * scale)
            HStack(spacing: 0) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Button {
                        profile.unit = unit
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(unit.rawValue)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(unit == profile.unit ? FitTheme.orange : .white.opacity(0.8))
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
    }

    private func weightTab(_ title: String, target: Bool) -> some View {
        Button { isTarget = target } label: {
            Text(title).font(FitTheme.body(18).weight(.semibold))
                .foregroundStyle(isTarget == target ? FitTheme.orange : .white.opacity(0.85))
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
    @State private var dragStart: Double?
    private let pointsPerUnit: CGFloat = 50

    private func setDisplayedWeight(_ value: Double) {
        let bounded = min(Double(unit.range.upperBound), max(Double(unit.range.lowerBound), value))
        let snapped = (bounded * 5).rounded() / 5
        kilograms = min(250, max(25, unit.kilograms(snapped)))
    }

    var body: some View {
        let displayed = unit.display(kilograms)
        let accent = FitTheme.orange
        Canvas { context, size in
            let centerTick = Int((displayed * 5).rounded())
            let visibleTicks = Int(size.width / 10 / 2) + 2
            for tick in (centerTick - visibleTicks)...(centerTick + visibleTicks) {
                guard (unit.range.lowerBound * 5 ... unit.range.upperBound * 5).contains(tick) else { continue }
                let major = tick.isMultiple(of: 5)
                let x = size.width / 2 + (CGFloat(tick) / 5 - displayed) * pointsPerUnit
                let selected = abs(x - size.width / 2) < 2
                if major {
                    let label = Text("\(tick / 5)")
                        .font(.system(size: 12, weight: selected ? .bold : .medium))
                        .foregroundColor(selected ? accent : .white.opacity(0.7))
                    context.draw(label, at: CGPoint(x: x, y: 8))
                }
                var tickPath = Path()
                tickPath.move(to: CGPoint(x: x, y: 24))
                tickPath.addLine(to: CGPoint(x: x, y: major ? 72 : 50))
                context.stroke(tickPath, with: .color(selected ? accent : .white.opacity(major ? 0.65 : 0.4)), lineWidth: major ? 1.3 : 1)
            }
        }
        .mask { LinearGradient(colors: [.clear, .black, .black, .black, .clear], startPoint: .leading, endPoint: .trailing) }
        .overlay(alignment: .top) {
            VStack(spacing: 5) {
                Capsule().fill(accent).frame(width: 2, height: 48)
                Image(systemName: "triangle.fill").font(.system(size: 11)).foregroundStyle(accent)
            }.padding(.top, 24).allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { value in
                if dragStart == nil { dragStart = displayed }
                setDisplayedWeight((dragStart ?? displayed) - value.translation.width / pointsPerUnit)
            }
            .onEnded { _ in
                dragStart = nil
                UISelectionFeedbackGenerator().selectionChanged()
            })
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

import SwiftUI
import WidgetKit

private enum WidgetStyle {
    static let accent = Color(red: 1, green: 0.30, blue: 0.03)
    static func body(_ size: CGFloat = 13) -> Font { .custom("Inter-Medium", size: size, relativeTo: .body) }
    static func metric(_ size: CGFloat = 30) -> Font { .custom("Orbitron-Bold", size: size, relativeTo: .title) }
}

struct FitOutWidgetView: View {
    let type: FitOutWidgetType
    let entry: FitOutWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var rendering
    private var state: FitOutWidgetState { entry.state }
    private var now: Date { entry.date }
    private var large: Bool { family == .systemLarge || family == .systemExtraLarge }
    private var accessory: Bool { [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family) }
    private var accent: Color { rendering == .fullColor ? WidgetStyle.accent : .primary }
    private var currentHealth: Bool { state.snapshot.health.isCurrent(at: now, calendar: .current) }
    private var nutrition: WidgetNutritionSnapshot? {
        guard let value = state.snapshot.nutrition, Calendar.current.isDate(value.date, inSameDayAs: now) else { return nil }
        return value
    }

    var body: some View {
        Group {
            if !state.snapshot.onboarded || entry.unavailable { setup }
            else if accessory { accessoryContent }
            else {
                switch type {
                case .water: waterContent
                case .workout: workoutContent
                case .overview: overviewContent
                default: metricContent
                }
            }
        }
        .font(WidgetStyle.body())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
        .widgetURL((!state.snapshot.onboarded || entry.unavailable ? .home : type == .workout && family == .systemSmall ? workoutAction.destination : type.destination).url)
        .privacySensitive()
    }

    @ViewBuilder private var setup: some View {
        if family == .accessoryInline { Label("Open FitOut", systemImage: "dumbbell") }
        else {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: type.symbol).foregroundStyle(accent)
                Text("Open FitOut").font(WidgetStyle.body(15))
                if !accessory { Text(entry.unavailable ? "Open the app to check widget setup." : "Finish setup to see your own data.").foregroundStyle(.secondary).font(WidgetStyle.body(12)).lineLimit(3).minimumScaleFactor(0.8) }
            }
        }
    }

    private func heading(_ text: String? = nil, symbol: String? = nil) -> some View {
        Label(text ?? type.title, systemImage: symbol ?? type.symbol)
            .font(WidgetStyle.body(12)).foregroundStyle(accent).widgetAccentable()
            .lineLimit(1).minimumScaleFactor(0.8)
    }
    private func number(_ value: String, unit: String, size: CGFloat = 30) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(WidgetStyle.metric(size)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65).invalidatableContent()
            if !unit.isEmpty { Text(unit).font(WidgetStyle.body(11)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
    private func open(_ text: String, _ destination: WidgetDestination, symbol: String = "arrow.up.right") -> some View {
        Link(destination: destination.url) { Label(text, systemImage: symbol).font(WidgetStyle.body(12)).lineLimit(1).minimumScaleFactor(0.8).frame(minHeight: 32) }
            .tint(accent)
    }
    @ViewBuilder private var freshness: some View {
        let measuredAt = [.steps, .calories, .sleep].contains(type) ? state.snapshot.health.measuredAt : state.snapshot.updatedAt
        if let measuredAt {
            HStack(spacing: 3) {
                Text("Synced")
                Text(measuredAt, style: .time)
                if !Calendar.current.isDate(measuredAt, inSameDayAs: now) { Text("· earlier day") }
            }.font(WidgetStyle.body(9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // Small = reading only. Medium = two quick logs. Large adds four amounts,
    // exact-entry undo, and the most recent log. Extra large adds a 7-day history.
    @ViewBuilder private var waterContent: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 10) {
                heading()
                Spacer(minLength: 0)
                number(waterValue, unit: "\(waterUnit) today")
                waterProgress
            }
        } else if family == .systemMedium {
            ViewThatFits(in: .vertical) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) { heading(); number(waterValue, unit: "\(waterUnit) today", size: 27); waterProgress }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) { waterButton(150); waterButton(500) }.frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { heading(); Spacer(); number(waterValue, unit: "\(waterUnit) today", size: 22) }
                    HStack { waterButton(150); waterButton(500) }
                }
            }
        } else if family == .systemExtraLarge {
            HStack(alignment: .top, spacing: 24) { expandedWater; Divider(); waterHistory.frame(maxWidth: .infinity) }
        } else {
            ViewThatFits(in: .vertical) {
                expandedWater
                VStack(alignment: .leading, spacing: 10) {
                    heading(); number(waterValue, unit: "\(waterUnit) today"); waterProgress
                    HStack { waterButton(150); waterButton(500) }
                    open("Water history & goals", .water)
                }
            }
        }
    }
    private var waterUnit: String { state.waterDisplayUnit == "L" ? "L" : "ml" }
    private var waterValue: String { (state.totalWater(at: now) / (waterUnit == "L" ? 1_000 : 1)).formatted(.number.precision(.fractionLength(0...(waterUnit == "L" ? 2 : 0)))) }
    @ViewBuilder private var waterProgress: some View {
        if let goal = state.goals.waterML, goal > 0 {
            ProgressView(value: min(goal, state.totalWater(at: now)), total: goal).tint(accent)
                .accessibilityLabel("Water goal").accessibilityValue("\(Int(state.totalWater(at: now) / goal * 100)) percent")
            Text("of \((goal / (waterUnit == "L" ? 1_000 : 1)).formatted(.number.precision(.fractionLength(0...2)))) \(waterUnit) goal").font(WidgetStyle.body(10)).foregroundStyle(.secondary)
        }
    }
    private var expandedWater: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading()
            number(waterValue, unit: "\(waterUnit) today", size: 34)
            waterProgress
            HStack(spacing: 6) {
                ForEach([150, 250, 500, 750], id: \.self) { waterButton($0) }
            }
            if let latest = state.latestWater(at: now) {
                HStack(spacing: 8) {
                    Text("Last: \(latest.milliliters) ml").font(WidgetStyle.body(11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button(intent: UndoWidgetWater(logID: latest.id)) { Label("Undo", systemImage: "arrow.uturn.backward").font(WidgetStyle.body(12)) }
                        .buttonStyle(.bordered).tint(accent).accessibilityLabel("Undo the displayed \(latest.milliliters) milliliter log")
                }
            }
            Spacer(minLength: 0)
            open("Water history & goals", .water)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func waterButton(_ amount: Int) -> some View {
        Button(intent: LogWidgetWater(milliliters: amount)) {
            Text("+\(amount) ml").font(WidgetStyle.body(13)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, minHeight: 32)
        }.buttonStyle(.borderedProminent).tint(accent).accessibilityLabel("Log \(amount) milliliters of water")
    }
    private var waterHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your FitOut logs").font(WidgetStyle.body(15))
            let days = (-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
            let totals = days.map { day in
                Double(state.water.filter { $0.date <= now && Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.milliliters })
            }
            WidgetBars(values: totals, tint: accent).frame(height: 100)
            HStack { Text("7 days ago"); Spacer(); Text("Today") }.font(WidgetStyle.body(10)).foregroundStyle(.secondary)
            Text("\(Int(totals.reduce(0, +))) ml logged over 7 days").font(WidgetStyle.body(13))
            Text("Apple Health water is included in today's total after opening FitOut. This history shows FitOut entries only.")
                .font(WidgetStyle.body(11)).foregroundStyle(.secondary)
        }
    }

    private var workoutTitle: String {
        if let active = state.snapshot.active { return active.title }
        if state.completed(on: now, through: now) { return "Workout complete" }
        if !state.snapshot.hasRoutine { return "Build your routine" }
        return state.plan(at: now)?.title ?? "Refresh your plan"
    }
    private var workoutSubtitle: String {
        if let active = state.snapshot.active { return "\(active.completedSets)/\(active.totalSets) sets · \(active.paused ? "Paused" : "In progress")" }
        if state.completed(on: now, through: now) { return "Saved to your history" }
        guard state.snapshot.hasRoutine else { return "Choose your training days" }
        guard let plan = state.plan(at: now) else { return "Open FitOut for today's schedule" }
        if plan.kind == "Rest day" { return "Your scheduled recovery day" }
        if plan.exerciseCount == 0 { return plan.kind == "Flexible day" ? "Choose how to train today" : "Add exercises to this day" }
        return "\(plan.exerciseCount) exercises" + (plan.minutes.map { " · \($0) min" } ?? "")
    }
    private var workoutAction: (title: String, destination: WidgetDestination) {
        if let active = state.snapshot.active { return (active.paused ? "Resume workout" : "Open workout", active.paused ? .startWorkout : .workout) }
        if state.completed(on: now, through: now) { return ("View history", .history) }
        guard state.snapshot.hasRoutine else { return ("Set up routine", .routine) }
        guard let plan = state.plan(at: now) else { return ("Open gym", .workout) }
        if plan.kind == "Workout", plan.exerciseCount > 0 { return ("Start workout", .startWorkout) }
        return ("View plan", .routine)
    }
    private var workoutContent: some View {
        ViewThatFits(in: .vertical) {
            workoutPanel(exerciseLimit: family == .systemExtraLarge ? 6 : large ? 4 : 0)
            workoutPanel(exerciseLimit: large ? 2 : 0)
            workoutPanel(exerciseLimit: 0)
        }
    }
    private func workoutPanel(exerciseLimit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading()
            Text(workoutTitle).font(WidgetStyle.body(large ? 22 : 16)).lineLimit(2).minimumScaleFactor(0.75)
            Text(workoutSubtitle).font(WidgetStyle.body(11)).foregroundStyle(.secondary).lineLimit(2)
            if exerciseLimit > 0, let plan = state.plan(at: now), !plan.exercises.isEmpty {
                Divider()
                ForEach(Array(plan.exercises.prefix(exerciseLimit).enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").foregroundStyle(accent).font(WidgetStyle.body(10))
                        Text(name).font(WidgetStyle.body(13)).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            if family != .systemSmall {
                HStack {
                    open(workoutAction.title, workoutAction.destination, symbol: state.snapshot.active == nil ? "play.fill" : "arrow.up.right")
                    Spacer(minLength: 0)
                    if state.snapshot.hasRoutine && family == .systemExtraLarge { open("Edit routine", .routine, symbol: "calendar") }
                }
            }
            if let end = state.snapshot.active?.restUntil, end > now, family != .systemSmall {
                HStack { Image(systemName: "timer"); Text(end, style: .timer); Text("rest") }.font(WidgetStyle.body(11)).foregroundStyle(.secondary)
            }
        }
    }

    private var reading: (value: String, unit: String, total: Double?, goal: Double?) {
        let health = state.snapshot.health
        switch type {
        case .steps:
            let value = currentHealth ? health.steps : nil
            return (value.map { Int($0).formatted() } ?? "—", "steps today", value, state.goals.steps)
        case .calories:
            let value = currentHealth ? health.activeCalories : nil
            return (value.map { Int($0).formatted() } ?? "—", "active kcal today", value, state.goals.activeCalories)
        case .sleep:
            let value = currentHealth ? health.sleepHours : nil
            let minutes = Int(((value ?? 0) * 60).rounded())
            return (value == nil ? "—" : "\(minutes / 60)h \(minutes % 60)m", "last night", value, state.goals.sleepHours)
        case .streak: return ("\(state.streak(at: now))", "consecutive days", Double(state.streak(at: now)), nil)
        case .volume:
            let value = state.volume(at: now).map { $0 * (state.snapshot.usesPounds ? 2.2046226218 : 1) }
            return (value.map { $0.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) } ?? "—", "\(state.snapshot.usesPounds ? "lb" : "kg")·reps this week", value, nil)
        case .nutrition:
            let value = nutrition?.calories
            return (value.map { ((nutrition?.estimatedEntries ?? 0) > 0 ? "≈" : "") + Int($0.rounded()).formatted() } ?? "—", "food kcal logged", value, nutrition?.targetCalories)
        default: return (waterValue, "\(waterUnit) today", state.totalWater(at: now), state.goals.waterML)
        }
    }
    private var metricContent: some View {
        ViewThatFits(in: .vertical) {
            metricPanel(expanded: large)
            metricPanel(expanded: false)
        }
    }
    private func metricPanel(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            heading()
            if family == .systemMedium {
                HStack(alignment: .center, spacing: 16) {
                    number(reading.value, unit: reading.unit, size: 27).frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) { metricDetail; open(actionTitle, type.destination) }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer(minLength: 0)
                number(reading.value, unit: reading.unit, size: large ? 32 : 27)
                metricDetail
                if expanded { expandedMetric }
                if large { Spacer(minLength: 0); open(actionTitle, type.destination) }
            }
            if type != .streak { freshness }
        }
    }
    private var actionTitle: String {
        switch type {
        case .streak: "Workout history"
        case .volume: "View progression"
        case .nutrition: "Open food diary"
        default: "View Health"
        }
    }
    @ViewBuilder private var metricDetail: some View {
        if let total = reading.total, let goal = reading.goal, goal > 0 {
            ProgressView(value: min(goal, total), total: goal).tint(accent)
            Text("Goal \(goal.formatted(.number.precision(.fractionLength(0...1))))\(type == .sleep ? " h" : "")")
                .font(WidgetStyle.body(11)).foregroundStyle(.secondary).lineLimit(1)
        } else if type == .streak { weekMarks }
        else if type == .volume {
            let previous = state.volume(at: now, offset: -1) ?? 0
            if let current = state.volume(at: now), previous > 0 {
                Text("\(((current - previous) / previous * 100).formatted(.number.sign(strategy: .always()).precision(.fractionLength(0))))% vs last week")
                    .font(WidgetStyle.body(11)).foregroundStyle(.secondary)
            } else { Text("Weighted sets only").font(WidgetStyle.body(11)).foregroundStyle(.secondary) }
        } else if reading.total == nil {
            Text(type == .nutrition ? ((nutrition?.entryCount ?? 0) > 0 ? "Energy not supplied" : "No food logged today") : "Open FitOut to sync").font(WidgetStyle.body(11)).foregroundStyle(.secondary).lineLimit(2)
        }
        if type == .nutrition, nutrition?.incomplete.contains("calories") == true { Text("Partial energy total").font(WidgetStyle.body(10)).foregroundStyle(.secondary) }
    }
    @ViewBuilder private var expandedMetric: some View {
        switch type {
        case .streak:
            let count = state.weekDays(at: now).filter { state.completed(on: $0, through: now) }.count
            Text("\(count) workout days this week").font(WidgetStyle.body(15))
            Text("Completed workouts · one credit per day").font(WidgetStyle.body(11)).foregroundStyle(.secondary)
        case .volume:
            WidgetBars(values: (-5...0).map { state.volume(at: now, offset: $0) ?? 0 }, tint: accent).frame(height: family == .systemExtraLarge ? 110 : 80)
            Text("Last 6 weeks · completed weighted working and drop sets").font(WidgetStyle.body(11)).foregroundStyle(.secondary)
        case .nutrition:
            if let value = nutrition {
                nutritionMacro("Protein", value.protein, value.targetProtein)
                nutritionMacro("Carbs", value.carbohydrates, value.targetCarbohydrates)
                nutritionMacro("Fat", value.fat, value.targetFat)
                Text("\(value.entryCount) logged foods" + (value.incomplete.isEmpty ? "" : " · some nutrients unavailable"))
                    .font(WidgetStyle.body(11)).foregroundStyle(.secondary)
            }
        default:
            let buckets = currentHealth ? (type == .steps ? state.snapshot.health.stepBuckets : type == .calories ? state.snapshot.health.calorieBuckets : state.snapshot.health.sleepBuckets) : []
            if reading.total != nil && buckets.contains(where: { $0 > 0 }) {
                WidgetBars(values: buckets, tint: accent).frame(height: family == .systemExtraLarge ? 110 : 80)
                Text(type == .sleep ? "Recorded sleep across the night" : "Activity by 2-hour window").font(WidgetStyle.body(11)).foregroundStyle(.secondary)
            }
            if reading.total == nil { Text("No reading shared for today").font(WidgetStyle.body(12)).foregroundStyle(.secondary) }
        }
    }
    private func nutritionMacro(_ title: String, _ value: Double?, _ target: Double?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + " g" } ?? "—")
            if let target { Text("/ \(target.formatted()) g").foregroundStyle(.secondary) }
        }.font(WidgetStyle.body(13))
    }
    private var weekMarks: some View {
        HStack(spacing: large ? 8 : 3) {
            ForEach(state.weekDays(at: now), id: \.self) { day in
                let done = state.completed(on: day, through: now)
                VStack(spacing: 4) {
                    if large { Text(day.formatted(.dateTime.weekday(.narrow))).font(WidgetStyle.body(9)).foregroundStyle(.secondary) }
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: large ? 22 : 12)).foregroundStyle(done ? accent : .secondary)
                }.frame(maxWidth: .infinity)
                    .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(done ? "completed" : "no completed workout")")
            }
        }
    }

    @ViewBuilder private var overviewContent: some View {
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 12) { heading(); overviewMetric(.water); overviewMetric(.steps) }
        } else {
            VStack(alignment: .leading, spacing: large ? 10 : 8) {
                heading()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: large ? 16 : 6) {
                    overviewMetric(.water); overviewMetric(.steps); overviewMetric(.calories); overviewMetric(.sleep)
                }
                if large {
                    Divider()
                    Link(destination: workoutAction.destination.url) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(workoutTitle).font(WidgetStyle.body(16)).lineLimit(1)
                                Text(workoutAction.title).font(WidgetStyle.body(11)).foregroundStyle(accent)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").foregroundStyle(accent)
                        }.frame(minHeight: 36)
                    }.tint(.primary)
                    HStack { waterButton(150); waterButton(500) }
                    if family == .systemExtraLarge {
                        weekMarks
                        HStack { Text("\(state.streak(at: now)) day streak"); Spacer(); open("Progression", .analytics) }.font(WidgetStyle.body(13))
                    }
                }
            }
        }
    }
    private func overviewMetric(_ metric: FitOutWidgetType) -> some View {
        let health = state.snapshot.health
        let value: String = switch metric {
        case .water: "\(waterValue) \(waterUnit)"
        case .steps: currentHealth ? health.steps.map { "\(Int($0).formatted())" } ?? "—" : "—"
        case .calories: currentHealth ? health.activeCalories.map { "\(Int($0)) kcal" } ?? "—" : "—"
        default: currentHealth ? health.sleepHours.map { "\(Int($0 * 60) / 60)h \(Int($0 * 60) % 60)m" } ?? "—" : "—"
        }
        let content = HStack(spacing: 6) {
                Image(systemName: metric.symbol).foregroundStyle(accent).widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text(value).font(WidgetStyle.body(large ? 19 : 14)).lineLimit(1).minimumScaleFactor(0.7).invalidatableContent()
                    if large { Text(metric.title).font(WidgetStyle.body(10)).foregroundStyle(.secondary).lineLimit(1) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if family == .systemSmall { content }
            else { Link(destination: metric.destination.url) { content }.tint(.primary) }
        }
    }

    @ViewBuilder private var accessoryContent: some View {
        if family == .accessoryInline {
            Label(type == .workout ? workoutTitle : type == .overview ? "\(waterValue) \(waterUnit) · \(state.streak(at: now)) day streak" : "\(reading.value) \(reading.unit)", systemImage: type.symbol)
        } else if family == .accessoryCircular {
            if let total = reading.total, let goal = reading.goal, goal > 0, type != .workout && type != .overview {
                Gauge(value: min(goal, total), in: 0...goal) { Image(systemName: type.symbol) } currentValueLabel: {
                    Text(type == .water ? waterValue : reading.value).font(.system(size: 11)).minimumScaleFactor(0.5)
                }.gaugeStyle(.accessoryCircular)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: type.symbol)
                    Text(type == .workout ? (state.snapshot.active != nil ? "Resume" : state.plan(at: now)?.kind == "Rest day" ? "Rest" : "Plan") : type == .overview ? "\(state.streak(at: now))d" : reading.value)
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                }
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(type == .overview ? "Water" : type.title, systemImage: type.symbol).font(.caption).lineLimit(1)
                    Text(type == .workout ? workoutTitle : type == .overview ? "\(waterValue) \(waterUnit)" : "\(reading.value) \(reading.unit)")
                        .font(.headline).lineLimit(2).minimumScaleFactor(0.65).invalidatableContent()
                }.frame(maxWidth: .infinity, alignment: .leading)
                if type == .water || type == .overview {
                    Button(intent: LogWidgetWater(milliliters: 150)) { Text("+150").font(.caption).frame(minWidth: 32, minHeight: 32) }
                        .buttonStyle(.bordered).accessibilityLabel("Log 150 milliliters")
                }
            }
        }
    }
}

private struct WidgetBars: View {
    let values: [Double]
    let tint: Color
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value > 0 ? tint : Color.secondary.opacity(0.2))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, geometry.size.height * max(0, value) / max(1, values.max() ?? 0)))
                }
            }.frame(height: geometry.size.height, alignment: .bottom)
        }.accessibilityLabel("Recorded history").accessibilityValue(values.map { $0.formatted(.number.precision(.fractionLength(0...1))) }.joined(separator: ", "))
    }
}

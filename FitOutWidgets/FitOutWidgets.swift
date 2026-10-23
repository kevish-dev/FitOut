import SwiftUI
import WidgetKit

enum FitOutWidgetType: String, CaseIterable {
    case water = "Water", workout = "Workout", steps = "Steps", calories = "Calories", sleep = "Sleep", streak = "Streak", volume = "Volume", overview = "Overview", nutrition = "Nutrition"
    var kind: String { "FitOut." + rawValue }
    var title: String {
        switch self {
        case .water: "Water intake"
        case .workout: "Today's workout"
        case .steps: "Steps"
        case .calories: "Active energy"
        case .sleep: "Last night's sleep"
        case .streak: "Workout streak"
        case .volume: "Training volume"
        case .overview: "Daily overview"
        case .nutrition: "Food & macros"
        }
    }
    var symbol: String {
        switch self {
        case .water: "drop.fill"
        case .workout, .volume: "dumbbell.fill"
        case .steps: "figure.walk"
        case .calories, .streak: "flame.fill"
        case .sleep: "moon.stars.fill"
        case .overview: "square.grid.2x2.fill"
        case .nutrition: "fork.knife"
        }
    }
    var destination: WidgetDestination {
        switch self {
        case .water: .water
        case .workout: .workout
        case .steps, .calories, .sleep: .health
        case .streak: .history
        case .volume: .analytics
        case .overview: .home
        case .nutrition: .nutrition
        }
    }
    var detail: String {
        switch self {
        case .water: "See today's water. Larger sizes add quick logging and undo."
        case .workout: "See your actual workout plan and open it to train."
        case .steps: "Your latest synced Apple Health steps and optional personal goal."
        case .calories: "Active energy burned from Apple Health, with your optional goal."
        case .sleep: "Your latest synced sleep reading. Larger sizes show the recorded night."
        case .streak: "Consecutive workout days and your real weekly activity."
        case .volume: "Weighted training volume and recent weekly progression."
        case .overview: "Your day at a glance. Larger sizes add water logging and workout shortcuts."
        case .nutrition: "Actual food calories and optional targets. Larger sizes add protein, carbs and fat."
        }
    }
}

struct FitOutWidgetEntry: TimelineEntry {
    let date: Date
    let state: FitOutWidgetState
    var unavailable = false
}
struct FitOutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FitOutWidgetEntry { FitOutWidgetEntry(date: .now, state: FitOutWidgetState()) }
    func getSnapshot(in context: Context, completion: @escaping (FitOutWidgetEntry) -> Void) { completion(read(at: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FitOutWidgetEntry>) -> Void) {
        let now = Date()
        let entry = read(at: now)
        let calendar = Calendar.current
        var entries = [entry]
        // Scheduled entries invalidate yesterday's Health totals and recalculate streaks
        // at midnight even when the app hasn't been launched.
        for offset in 1...2 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) {
                entries.append(FitOutWidgetEntry(date: midnight, state: entry.state, unavailable: entry.unavailable))
            }
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
    private func read(at date: Date) -> FitOutWidgetEntry {
        do {
            let state = try WidgetSharedStore.live().read()
            return FitOutWidgetEntry(date: max(date, .now), state: state)
        }
        catch { return FitOutWidgetEntry(date: date, state: FitOutWidgetState(), unavailable: true) }
    }
}

struct FitOutConfiguredWidget: Widget {
    let type: FitOutWidgetType
    init() { type = .water }
    init(type: FitOutWidgetType) { self.type = type }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: type.kind, provider: FitOutTimelineProvider()) { entry in
            FitOutWidgetView(type: type, entry: entry)
        }
        .configurationDisplayName(type.title)
        .description(type.detail)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main struct FitOutWidgets: WidgetBundle {
    var body: some Widget {
        FitOutConfiguredWidget(type: .water)
        FitOutConfiguredWidget(type: .workout)
        FitOutConfiguredWidget(type: .steps)
        FitOutConfiguredWidget(type: .calories)
        FitOutConfiguredWidget(type: .sleep)
        FitOutConfiguredWidget(type: .streak)
        FitOutConfiguredWidget(type: .volume)
        FitOutConfiguredWidget(type: .overview)
        FitOutConfiguredWidget(type: .nutrition)
    }
}

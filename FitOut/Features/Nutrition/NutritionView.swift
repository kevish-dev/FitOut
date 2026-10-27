import SwiftUI
import Combine

private enum NutritionSheet: Identifiable {
    case food(NutritionMeal), quick(NutritionMeal), entry(FoodLogEntry), targets, library, recipe, copy, history, water, details, privacy, saved(NutritionSavedMeal)
    var id: String {
        switch self {
        case .food(let meal): "food-" + meal.rawValue
        case .quick(let meal): "quick-" + meal.rawValue
        case .entry(let entry): entry.id.uuidString
        case .saved(let meal): meal.id.uuidString
        case .targets: "targets"
        case .library: "library"
        case .recipe: "recipe"
        case .copy: "copy"
        case .history: "history"
        case .water: "water"
        case .details: "details"
        case .privacy: "privacy"
        }
    }
}

struct NutritionView: View {
    @Environment(\.appNavigationStyle) private var navigationStyle
    let container: AppContainer
    @State private var date = Date()
    @State private var sheet: NutritionSheet?
    @Environment(\.scenePhase) private var phase
    private var store: NutritionStore { container.nutrition }
    private var summary: NutritionDaySummary { store.summary(on: date) }
    private var target: NutritionValues { store.target(on: date) }
    private var today: Bool { Calendar.current.isDateInToday(date) }
    private var waterUnit: String { container.hydration.waterDisplayUnit }
    private var waterTotal: Double {
        today ? container.hydration.state.totalWater(at: .now) : Double(container.hydration.state.localWater(at: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!.addingTimeInterval(-1)))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                header
                dateSelector
                energySummary
                quickActions
                if let routine = container.gym.activeRoutine, routine.hasStarted(at: date), let day = RoutineSchedule.day(in: routine, at: date), day.kind == .workout {
                    Label("Gym · \(day.title) · \(day.exercises.count) exercises planned", systemImage: "dumbbell")
                        .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
                mealTimeline
                hydration
                if let insight = insight { Label(insight, systemImage: "chart.xyaxis.line").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary).padding(.vertical, 4) }
                HStack {
                    Button("History & trends", systemImage: "chart.bar.xaxis") { sheet = .history }
                    Spacer()
                    Button("Privacy", systemImage: "lock") { sheet = .privacy }
                }.font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary).frame(minHeight: 44)
                Text("Totals describe what you've logged, including any estimates. Unlogged meals and unavailable nutrients are not zero intake.")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            .frame(maxWidth: 560).padding(.horizontal, FitTheme.pageInset).padding(.top, 16).padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize)
        .background(FitTheme.dashboardBackground).foregroundStyle(FitTheme.textPrimary).tint(FitTheme.dashboardAccent)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { do { try store.reload() } catch { store.error = error.localizedDescription }; container.hydration.refresh() }
        .safeAreaInset(edge: .bottom) {
            if store.deletedEntry != nil {
                HStack { Text("Food entry removed"); Spacer(); Button("Undo") { store.undoDelete() }; Button("Dismiss", systemImage: "xmark") { store.deletedEntry = nil }.labelStyle(.iconOnly) }
                    .font(FitTheme.button(13)).padding(16).dashboardGlass(in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, FitTheme.pageInset)
                    .workoutControlClearance("nutrition.undo.actions")
            }
        }
        .sheet(item: $sheet) { route in sheetContent(route) }
        .alert("Couldn't save nutrition", isPresented: Binding(get: { store.error != nil && sheet == nil }, set: { if !$0 { store.error = nil } })) { Button("OK", role: .cancel) { store.error = nil } } message: { Text(store.error ?? "") }
        .task { container.hydration.refresh() }
        .onChange(of: phase) { _, value in if value == .active { container.hydration.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in date = .now; container.hydration.refresh() }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOOD & NUTRITION").font(FitTheme.medium(10)).tracking(2).foregroundStyle(FitTheme.dashboardAccent)
            Text("Fuel your day.").font(FitTheme.hero(30)).lineLimit(2)
            Text("Your meals, your rhythm.").font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary)
        }.padding(.trailing, navigationStyle == .topRight ? 68 : 0).accessibilityAddTraits(.isHeader)
    }
    private var dateSelector: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { moveDate(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous day")
                DatePicker("Nutrition date", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden().datePickerStyle(.compact).frame(maxWidth: .infinity)
                Button { moveDate(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(today).accessibilityLabel("Next day")
            }
            if !today { Button { date = .now } label: { Text("Back to today").font(FitTheme.button(12)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) } }
        }
        .font(FitTheme.body(14)).padding(.horizontal, 4)
        .dashboardGlass(in: RoundedRectangle(cornerRadius: 14))
    }
    private var energySummary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CALORIES LOGGED").font(FitTheme.medium(10)).tracking(1.2).foregroundStyle(FitTheme.textSecondary)
                    Text(NutritionUI.value(summary.values.calories)).font(FitTheme.metric(38)).lineLimit(1).minimumScaleFactor(0.6)
                    if let goal = target.calories {
                        Text("of \(NutritionUI.value(goal)) kcal target").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                        if summary.isComplete(.calories), let consumed = summary.values.calories {
                            Text("\(NutritionUI.value(abs(goal - consumed))) kcal \(consumed > goal ? "above target" : "remaining")")
                                .font(FitTheme.medium(12)).foregroundStyle(FitTheme.dashboardAccent)
                        }
                    } else { Button { sheet = .targets } label: { Label("Set your targets", systemImage: "slider.horizontal.3").font(FitTheme.button(12)).frame(minHeight: 44).contentShape(Rectangle()) } }
                    if summary.entries.isEmpty { Text("No food logged for this day").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
                    else if !summary.isComplete(.calories) { Text("Partial total · some energy values missing").font(FitTheme.body(11)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let goal = target.calories, goal > 0 {
                    ZStack {
                        Circle().stroke(FitTheme.textPrimary.opacity(0.07), lineWidth: 9)
                        Circle().trim(from: 0, to: min(1, (summary.values.calories ?? 0) / goal)).stroke(FitTheme.dashboardAccent, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: "fork.knife").font(.system(size: 25, weight: .light)).foregroundStyle(FitTheme.dashboardAccent)
                    }.frame(width: 76, height: 76).accessibilityHidden(true)
                }
            }
            Divider().overlay(FitTheme.textPrimary.opacity(0.06))
            Button { sheet = .details } label: {
                HStack(alignment: .top, spacing: 16) {
                    macro(.protein, title: "Protein"); macro(.carbohydrates, title: "Carbs"); macro(.fat, title: "Fat")
                }
            }.buttonStyle(.fitPlain).accessibilityLabel("Open daily nutrient breakdown")
            HStack {
                if summary.estimateCount > 0 { Text("\(summary.estimateCount) estimated \(summary.estimateCount == 1 ? "entry" : "entries")").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
                Spacer()
                Button("Edit targets") { sheet = .targets }.font(FitTheme.medium(11))
            }
        }.padding(FitTheme.cardInset).background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func macro(_ key: NutritionNutrient, title: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
            Text(NutritionUI.value(summary.values[key], unit: "g", decimals: 1)).font(FitTheme.section(17)).lineLimit(1).minimumScaleFactor(0.65)
            if let goal = target[key], goal > 0 {
                ProgressView(value: min(goal, summary.values[key] ?? 0), total: goal).tint(FitTheme.dashboardAccent.opacity(key == .protein ? 1 : 0.5))
                Text("of \(NutritionUI.value(goal)) g").font(FitTheme.body(10)).foregroundStyle(FitTheme.textSecondary)
            } else { Text("No target set").font(FitTheme.body(10)).foregroundStyle(FitTheme.textSecondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var quickActions: some View {
        HStack(spacing: 12) {
            NutritionPrimaryButton(title: "Add food") { sheet = .food(.suggested()) }.accessibilityIdentifier("nutritionAddFood")
            Menu {
                Button("Quick add calories / macros", systemImage: "number") { sheet = .quick(.suggested()) }
                Button("Create recipe", systemImage: "book.closed") { sheet = .recipe }
                Button("Foods, recipes & saved meals", systemImage: "books.vertical") { sheet = .library }
                Button("Copy a meal from another day", systemImage: "doc.on.doc") { sheet = .copy }
                Button("Add water", systemImage: "drop") { sheet = .water }
                if let last = store.entries.first { Button("Repeat last: \(last.portion.food.name)") { _ = store.repeatEntry(last, on: date) } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 50, height: 48)
                    .dashboardGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
            }.accessibilityLabel("More nutrition actions")
        }
    }
    private var mealTimeline: some View {
        VStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
            HStack { Text(today ? "Today's meals" : "Meals").font(FitTheme.section(20)); Spacer(); Button("Library") { sheet = .library }.font(FitTheme.medium(12)) }
            ForEach(NutritionMeal.allCases) { meal in
                let entries = store.entries(on: date, meal: meal)
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: meal.symbol).font(.system(size: 17)).foregroundStyle(FitTheme.textSecondary).frame(width: 24)
                        Text(meal.rawValue).font(FitTheme.section(16))
                        Spacer()
                        if !entries.isEmpty { Text("\(NutritionUI.value(NutritionValues.sum(entries.map { $0.portion.values }).calories)) kcal").font(FitTheme.medium(12)).foregroundStyle(FitTheme.textSecondary) }
                        Menu {
                            Button("Add food", systemImage: "plus") { sheet = .food(meal) }
                            Button("Quick add", systemImage: "number") { sheet = .quick(meal) }
                            if !entries.isEmpty {
                                Button("Duplicate this meal") { _ = store.copyMeal(from: date, meal: meal, to: date, destinationMeal: meal) }
                                Button("Save for reuse") { sheet = .saved(NutritionSavedMeal(name: meal.rawValue, items: entries.map { $0.portion.independentCopy() })) }
                            }
                        } label: { Image(systemName: "plus.circle").font(.system(size: 20)).frame(width: 44, height: 44) }.accessibilityLabel("\(meal.rawValue) actions")
                    }
                    if entries.isEmpty {
                        Button { sheet = .food(meal) } label: { Text("Add to \(meal.rawValue.lowercased())").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
                    } else {
                        ForEach(entries) { entry in entryRow(entry) }
                    }
                    Rectangle().fill(FitTheme.textPrimary.opacity(0.07)).frame(height: 1)
                }
            }
        }
    }
    private func entryRow(_ entry: FoodLogEntry) -> some View {
        Button { sheet = .entry(entry) } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.portion.food.name).font(FitTheme.medium(14)).foregroundStyle(FitTheme.textPrimary)
                    Text(entry.portion.label).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                    Text(entry.portion.food.sourceTitle).font(FitTheme.body(10)).foregroundStyle(FitTheme.textSecondary)
                }
                Spacer(minLength: 0)
                Text(NutritionUI.value(entry.portion.values.calories)).font(FitTheme.section(15)).foregroundStyle(FitTheme.textPrimary)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(FitTheme.textSecondary).padding(.top, 3)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.fitPlain).contextMenu {
            Button("Edit") { sheet = .entry(entry) }
            Button("Duplicate") { _ = store.repeatEntry(entry, on: date) }
            Menu("Move to meal") { ForEach(NutritionMeal.allCases) { meal in Button(meal.rawValue) { var value = entry; value.meal = meal; _ = store.saveEntry(value) } } }
            Button("Delete", role: .destructive) { _ = store.deleteEntry(entry) }
        }
    }
    private var hydration: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Water", systemImage: "drop").font(FitTheme.section(18))
                Spacer()
                Button("History") { sheet = .water }.font(FitTheme.medium(12))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(NutritionUI.value(waterTotal / (waterUnit == "L" ? 1_000 : 1), unit: waterUnit, decimals: 2)).font(FitTheme.metric(27))
                if let goal = container.hydration.state.goals.waterML { Text("/ \(NutritionUI.value(goal / (waterUnit == "L" ? 1_000 : 1), unit: waterUnit, decimals: 2))").font(FitTheme.body(14)).foregroundStyle(FitTheme.textSecondary) }
                Spacer()
            }
            HStack(spacing: 12) {
                ForEach([250, 500], id: \.self) { amount in
                    Button { container.hydration.log(amount, at: NutritionDates.timestamp(on: date)) } label: {
                        Text("+\(amount) ml").font(FitTheme.button(13)).frame(maxWidth: .infinity, minHeight: 44)
                            .dashboardGlass(in: Capsule(), interactive: true)
                    }.buttonStyle(.fitPlain)
                }
            }
            if let latest = container.hydration.state.water.filter({ Calendar.current.isDate($0.date, inSameDayAs: date) }).max(by: { $0.date < $1.date }) {
                Button("Undo last \(latest.milliliters) ml") { container.hydration.remove(latest.id) }.font(FitTheme.body(11))
            }
            if !today { Text("Past dates show FitOut water logs only.").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
            if let error = container.hydration.error { Text(error).font(FitTheme.body(12)).foregroundStyle(.orange) }
        }.padding(FitTheme.cardInset).background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
    private var insight: String? {
        if let goal = target.protein, let protein = summary.values.protein, summary.isComplete(.protein), goal > protein {
            return "\(NutritionUI.value(goal - protein, unit: "g", decimals: 1)) protein remains against your target, based on this day's logged foods."
        }
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: date) }.map { store.summary(on: $0) }.filter { $0.isComplete(.calories) }
        guard days.count >= 3 else { return nil }
        let average = days.compactMap { $0.values.calories }.reduce(0, +) / Double(days.count)
        return "\(NutritionUI.value(average)) kcal logged on average across \(days.count) days with complete energy values in the past week."
    }
    private func moveDate(_ value: Int) { date = min(.now, Calendar.current.date(byAdding: .day, value: value, to: date) ?? date) }
    @ViewBuilder private func sheetContent(_ route: NutritionSheet) -> some View {
        switch route {
        case .food(let meal): FoodSelectionSheet(store: store, date: date, meal: meal) { portion, timestamp, meal in store.saveEntry(FoodLogEntry(date: timestamp, meal: meal, portion: portion)) }
        case .quick(let meal): NutritionQuickAddView(store: store, date: date, meal: meal)
        case .entry(let entry): NavigationStack { FoodPortionEditor(store: store, portion: entry.portion, date: entry.date, meal: entry.meal, note: entry.note, title: "Edit food entry") { portion, timestamp, meal, note in var value = entry; value.portion = portion; value.date = timestamp; value.meal = meal; value.note = note; return store.saveEntry(value) } }
        case .targets: NutritionTargetView(store: store, date: date)
        case .library: NutritionLibraryView(store: store, date: date)
        case .recipe: NutritionRecipeEditor(store: store, recipe: NutritionRecipe())
        case .saved(let meal): NutritionSavedMealEditor(store: store, meal: meal)
        case .copy: NutritionCopyMealView(store: store, destination: date)
        case .history: NutritionHistoryView(store: store, hydration: container.hydration, endDate: date) { date = $0; sheet = nil }
        case .water: NavigationStack { HydrationView(store: container.hydration, health: container.health, selectedDate: date, reminders: container.hydrationReminders).toolbar { Button("Close") { sheet = nil } } }
        case .details: NavigationStack { NutritionBreakdownView(summary: summary).toolbar { Button("Close") { sheet = nil } } }
        case .privacy: NutritionPrivacyView(store: store, hydration: container.hydration)
        }
    }
}

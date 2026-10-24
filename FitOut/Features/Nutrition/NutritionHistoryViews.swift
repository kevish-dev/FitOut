import SwiftUI
import Charts
import UniformTypeIdentifiers

struct NutritionTargetView: View {
    let store: NutritionStore
    let date: Date
    @State private var values = NutritionValues()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NutritionValueFields(values: $values)
                } header: { Text("Your daily targets") } footer: {
                    Text("Optional personal targets, effective from \(date.formatted(date: .abbreviated, time: .omitted)). Leave any value blank to skip it. Earlier dates keep their previous target. Exercise calories are not added to your allowance.")
                }
                Section { Button("Clear targets from this date") { values = NutritionValues() } }
                if !NutritionTarget(effectiveDate: date, values: values).isValid { Text("Enter positive targets, or leave them blank.").foregroundStyle(.orange) }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.nutritionForm().navigationTitle("Nutrition targets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.saveTarget(values, from: date) { dismiss() } }.disabled(!NutritionTarget(effectiveDate: date, values: values).isValid) }
            }
            .onAppear { values = store.target(on: date) }
        }
    }
}

struct NutritionBreakdownView: View {
    let summary: NutritionDaySummary
    var body: some View {
        List {
            Section("Logged nutrient totals") {
                ForEach(NutritionNutrient.allCases) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(key.title, value: NutritionUI.value(summary.values[key], unit: key.unit, decimals: 1))
                        Text("Complete values in \(summary.knownCount(key)) of \(summary.entries.count) entries" + (summary.isComplete(key) ? "" : " · partial or unavailable"))
                            .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                    }
                }
            }
            ForEach(NutritionMeal.allCases) { meal in
                let entries = summary.entries.filter { $0.meal == meal }
                if !entries.isEmpty {
                    Section(meal.rawValue) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.portion.food.name).font(FitTheme.section(15))
                                Text("\(entry.portion.label) · \(entry.portion.food.sourceTitle)").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                                Text("\(NutritionUI.value(entry.portion.values.calories)) kcal · P \(NutritionUI.value(entry.portion.values.protein, decimals: 1)) · C \(NutritionUI.value(entry.portion.values.carbohydrates, decimals: 1)) · F \(NutritionUI.value(entry.portion.values.fat, decimals: 1)) g")
                                    .font(FitTheme.body(12))
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }
            Text("A total includes the available values only. Blank nutrients are not zero; estimates retain their source label. This diary cannot determine what was eaten but not logged.")
                .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
        }.nutritionForm().navigationTitle("Daily breakdown")
    }
}

struct NutritionHistoryDay: Identifiable {
    let date: Date
    let summary: NutritionDaySummary
    let waterML: Double?
    var id: Date { date }
    static func nutrient(_ metric: Int) -> NutritionNutrient { switch metric { case 1: .protein; case 3: .carbohydrates; case 4: .fat; default: .calories } }
    func value(_ metric: Int) -> Double? { metric == 2 ? waterML : summary.values[Self.nutrient(metric)] }
    func isComplete(_ metric: Int) -> Bool { metric == 2 || summary.isComplete(Self.nutrient(metric)) }
}
struct NutritionHistoryView: View {
    let store: NutritionStore
    let hydration: HydrationStore
    @State var endDate: Date
    let onSelect: (Date) -> Void
    @State private var range = 7
    @State private var metric = 0
    @Environment(\.dismiss) private var dismiss
    private var days: [NutritionHistoryDay] {
        (0..<range).reversed().compactMap { offset in
            guard let day = Calendar.current.date(byAdding: .day, value: -offset, to: Calendar.current.startOfDay(for: endDate)) else { return nil }
            let logs = hydration.state.water.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.date <= .now }
            return NutritionHistoryDay(date: day, summary: store.summary(on: day), waterML: logs.isEmpty ? nil : Double(logs.reduce(0) { $0 + $1.milliliters }))
        }
    }
    private var completeDays: [NutritionHistoryDay] { days.filter { $0.value(metric) != nil && $0.isComplete(metric) } }
    private var unit: String { metric == 2 ? "ml water" : NutritionHistoryDay.nutrient(metric).unit }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Through", selection: $endDate, in: ...Date(), displayedComponents: .date)
                    Picker("Range", selection: $range) { Text("7 days").tag(7); Text("30 days").tag(30) }.pickerStyle(.segmented)
                    Picker("Metric", selection: $metric) { Text("Calories").tag(0); Text("Protein").tag(1); Text("Carbohydrates").tag(3); Text("Fat").tag(4); Text("Water").tag(2) }
                }
                Section {
                    if days.contains(where: { $0.value(metric) != nil }) {
                        Chart(days) { day in
                            if let value = day.value(metric) {
                                BarMark(x: .value("Date", day.date, unit: .day), y: .value(unit, value))
                                    .foregroundStyle(day.isComplete(metric) ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                                    .cornerRadius(3)
                                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue("\(value.formatted()) \(unit) logged\(day.isComplete(metric) ? "" : ", partial")")
                            }
                            if metric != 2, let goal = store.target(on: day.date)[NutritionHistoryDay.nutrient(metric)],
                               let end = Calendar.current.date(byAdding: .day, value: 1, to: day.date) {
                                RuleMark(xStart: .value("From", day.date), xEnd: .value("To", end), y: .value("Target", goal))
                                    .foregroundStyle(FitTheme.textPrimary.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            }
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) { AxisValueLabel(format: .dateTime.day()) } }
                        .frame(height: 180)
                        if metric != 2 { Text("Grey bars: incomplete values. Dashed line: that date's configured target. Gaps: no value logged.").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
                    } else { ContentUnavailableView("No values logged in this range", systemImage: "chart.bar", description: Text("Your recorded data will appear here.")) }
                    if completeDays.count >= 3 {
                        let average = completeDays.compactMap { $0.value(metric) }.reduce(0, +) / Double(completeDays.count)
                        LabeledContent("Logged-day average", value: NutritionUI.value(average, unit: unit, decimals: 1))
                        Text("Based on \(completeDays.count) logged days\(metric == 2 ? "" : " with complete values for this metric"). Unlogged days are excluded.").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                    }
                    LabeledContent("Days with food logs", value: "\(days.filter { !$0.summary.entries.isEmpty }.count) / \(range)")
                    if metric == 2 { Text("Water history shows FitOut logs only, excluding unsaved historical Apple Health readings.").font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary) }
                } header: { Text("\(days.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "") – \(endDate.formatted(date: .abbreviated, time: .omitted))") }
                macroDistribution
                Section("Open a day") {
                    ForEach(days.reversed()) { day in
                        Button { onSelect(day.date); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(FitTheme.medium(14)).foregroundStyle(FitTheme.textPrimary)
                                    Text(day.summary.entries.isEmpty ? "No food logged" : "\(day.summary.entries.count) food entries" + (day.summary.isComplete(.calories) ? "" : " · incomplete energy"))
                                        .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                                }
                                Spacer()
                                Text(NutritionUI.value(day.value(metric), unit: unit, decimals: 1)).font(FitTheme.medium(13)).foregroundStyle(FitTheme.textPrimary)
                            }.padding(.vertical, 5)
                        }
                    }
                }
            }.nutritionForm().navigationTitle("Nutrition history")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
    @ViewBuilder private var macroDistribution: some View {
        let complete = days.filter { $0.summary.isComplete(.protein) && $0.summary.isComplete(.carbohydrates) && $0.summary.isComplete(.fat) }
        if complete.count >= 3 {
            let values = NutritionValues.sum(complete.map { $0.summary.values })
            let energy = [("Protein", (values.protein ?? 0) * 4), ("Carbs", (values.carbohydrates ?? 0) * 4), ("Fat", (values.fat ?? 0) * 9)]
            let total = energy.reduce(0) { $0 + $1.1 }
            if total > 0 {
                Section("Macro distribution · logged days") {
                    ForEach(energy, id: \.0) { item in
                        HStack {
                            Text(item.0).font(FitTheme.medium(13)).frame(width: 66, alignment: .leading)
                            ProgressView(value: item.1, total: total).tint(FitTheme.dashboardAccent)
                            Text("\(Int((item.1 / total * 100).rounded()))%").font(FitTheme.medium(12)).frame(width: 38, alignment: .trailing)
                        }
                    }
                    Text("Across \(complete.count) days with all three macros supplied. Energy shares use 4/4/9 kcal per gram and can differ from database calories.")
                        .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }
            }
        }
    }
}

struct NutritionExport: Codable {
    var formatVersion = 1
    var exportedAt = Date()
    let customFoods: [NutritionFood]
    let foodEntries: [FoodLogEntry]
    let recipes: [NutritionRecipe]
    let savedMeals: [NutritionSavedMeal]
    let targets: [NutritionTarget]
    let preferences: NutritionPreferences
    let fitOutWaterEntries: [WidgetWaterLog]
    let waterGoalML: Double?
}
struct NutritionJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct NutritionPrivacyView: View {
    let store: NutritionStore
    let hydration: HydrationStore
    @State private var export: NutritionJSONDocument?
    @State private var exporting = false
    @State private var deleting = false
    @State private var deletingWater = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Your data") {
                    Text("Food logs, custom foods, recipes and targets are stored locally. Core logging works offline and requires no Health connection or account.")
                    Button("Export nutrition & FitOut water", systemImage: "square.and.arrow.up") { makeExport() }
                    Text("JSON export includes historical food snapshots and sources. Apple Health readings are not included.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
                Section("Data sources") {
                    Text("The offline library contains USDA SR Legacy reference foods, a published paneer label and explicitly marked recipe estimates. Raw and cooked entries are separate. Current package labels may differ.")
                    Link("USDA FoodData Central · public-domain data", destination: URL(string: "https://fdc.nal.usda.gov/")!)
                }
                Section("Delete records") {
                    Button("Delete all nutrition data", role: .destructive) { deleting = true }
                    Button("Delete FitOut water history", role: .destructive) { deletingWater = true }
                }
                if let message { Text(message).font(FitTheme.body(13)) }
                if let error = store.error ?? hydration.error { Text(error).foregroundStyle(.orange) }
            }.nutritionForm().navigationTitle("Nutrition privacy")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileExporter(isPresented: $exporting, document: export, contentType: .json, defaultFilename: "FitOut-nutrition-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
                if case .failure(let error) = result { message = error.localizedDescription }
                else { message = "Export saved." }
            }
            .confirmationDialog("Delete nutrition data?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete nutrition data", role: .destructive) { if store.deleteAllNutrition() { message = "Nutrition data deleted." } }
            } message: { Text("Deletes food history, custom foods, recipes, saved meals, targets and favorites. Water, workouts and profile remain available.") }
            .confirmationDialog("Delete all FitOut water entries?", isPresented: $deletingWater, titleVisibility: .visible) {
                Button("Delete water history", role: .destructive) { if hydration.clearHistory() { message = "FitOut water entries deleted." } }
            } message: { Text("Removes FitOut water entries from the app and widgets. Apple Health records are managed in Health.") }
        }
    }
    private func makeExport() {
        do {
            hydration.refresh()
            let value = NutritionExport(customFoods: store.customFoods, foodEntries: store.entries, recipes: store.recipes, savedMeals: store.savedMeals, targets: store.targets, preferences: store.preferences, fitOutWaterEntries: hydration.state.water, waterGoalML: hydration.state.goals.waterML)
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            export = NutritionJSONDocument(data: try encoder.encode(value)); exporting = true
        } catch { message = error.localizedDescription }
    }
}

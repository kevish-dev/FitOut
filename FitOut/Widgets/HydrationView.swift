import SwiftUI
import Combine

struct HydrationView: View {
    @Bindable var store: HydrationStore
    let health: HealthAccessService
    var selectedDate: Date? = nil
    var reminders: HydrationReminderStore? = nil
    @State private var amount = 250
    @State private var showingGoals = false
    @State private var now = Date()
    @State private var date = Date()
    @State private var loaded = false
    @State private var editing: WidgetWaterLog?
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var today: Bool { Calendar.current.isDate(date, inSameDayAs: now) }
    private var logs: [WidgetWaterLog] { store.state.water.filter { $0.date <= now && Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { $0.date > $1.date } }
    private var total: Double { today ? store.state.totalWater(at: now) : Double(logs.reduce(0) { $0 + $1.milliliters }) }
    private var liters: Bool { store.waterDisplayUnit == "L" }
    var body: some View {
        List {
            Section {
                DatePicker("Water history date", selection: $date, in: ...Date(), displayedComponents: .date)
                Text("\((liters ? total / 1_000 : total).formatted(.number.precision(.fractionLength(0...(liters ? 2 : 0))))) \(liters ? "L" : "ml")")
                    .font(FitTheme.metric(30)).foregroundStyle(FitTheme.dashboardAccent)
                    .contentTransition(.numericText()).animation(FitMotion.change(reduceMotion: reduceMotion), value: total)
                if let goal = store.state.goals.waterML {
                    ProgressView(value: min(goal, total), total: goal)
                        .animation(FitMotion.change(reduceMotion: reduceMotion), value: total)
                    Text("Your current goal: \(Int(goal)) ml").font(FitTheme.body(13))
                }
                Text(today ? "FitOut logs plus water shared by Apple Health. Local entries are not written back to Health." : "Past dates show FitOut water logs only; historical Apple Health readings are not imported here.")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }
            Section("Quick log") {
                ViewThatFits { HStack { quick(150); quick(250); quick(500) }; VStack { quick(150); quick(250); quick(500) } }
                Stepper("\(amount) ml", value: $amount, in: 50...2_000, step: 50)
                Button("Log \(amount) ml", systemImage: "plus.circle.fill") { store.log(amount, at: NutritionDates.timestamp(on: date)) }
            }
            Section("FitOut water entries") {
                if logs.isEmpty { Text("No FitOut water logged for this date.").foregroundStyle(.secondary) }
                ForEach(logs) { log in
                    waterRow(log)
                }
                if let last = logs.first { Button("Undo last \(last.milliliters) ml") { store.remove(last.id) } }
            }
            Button("Water & widget goals", systemImage: "slider.horizontal.3") { showingGoals = true }
            if let reminders {
                NavigationLink { HydrationReminderView(store: reminders) } label: { Label("Water reminder", systemImage: "bell") }
            }
            if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.orange) }
        }
        .font(FitTheme.body(15)).navigationTitle("Water intake")
        .scrollContentBackground(.hidden).background(FitTheme.dashboardBackground).tint(FitTheme.dashboardAccent)
        .task { if !loaded { date = selectedDate ?? .now; loaded = true }; now = .now; store.refresh() }
        .onChange(of: phase) { _, value in if value == .active { now = .now; store.refresh() } }
        .onChange(of: store.state.water) { _, _ in now = .now }
        .onChange(of: store.state.snapshot.health.measuredAt) { _, _ in now = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in if today { date = .now }; now = .now; store.refresh() }
        .refreshable { await health.refreshOverview(); store.refresh(); now = .now }
        .sheet(isPresented: $showingGoals) { WidgetGoalsView(store: store) }
        .sheet(item: $editing) { log in WaterEntryEditor(store: store, log: log) }
    }
    private func quick(_ value: Int) -> some View {
        Button { store.log(value, at: NutritionDates.timestamp(on: date)) } label: {
            Text("+\(value) ml").font(FitTheme.button(14)).frame(maxWidth: .infinity, minHeight: 44).dashboardGlass(in: Capsule(), interactive: true)
        }.buttonStyle(RoutineEditorPressStyle())
    }
    private func waterRow(_ log: WidgetWaterLog) -> some View {
        Button { editing = log } label: {
            HStack {
                Image(systemName: "drop")
                Text(String(log.milliliters) + " ml")
                Spacer()
                Text(log.date, style: .time).foregroundStyle(FitTheme.textSecondary)
            }.foregroundStyle(FitTheme.textPrimary)
        }.swipeActions { Button("Delete", role: .destructive) { store.remove(log.id) } }
    }
}

private struct WaterEntryEditor: View {
    let store: HydrationStore
    let log: WidgetWaterLog
    @State private var amount = 250.0
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                NutritionNumberField(title: "Amount (ml)", value: Binding(get: { amount }, set: { amount = $0 ?? 0 }))
                DatePicker("Time", selection: $date, in: ...Date())
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.nutritionForm().navigationTitle("Edit water entry")
            .onAppear { amount = Double(log.milliliters); date = log.date }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.edit(log.id, amount: Int(amount.rounded()), date: date); if store.error == nil { dismiss() } }.disabled(!amount.isFinite || !(1...5_000).contains(amount)) }
            }
        }
    }
}

struct WidgetGoalsView: View {
    let store: HydrationStore
    @State private var goals = WidgetGoals()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    goal("Water (ml)", value: $goals.waterML)
                    goal("Steps", value: $goals.steps)
                    goal("Active energy (kcal)", value: $goals.activeCalories)
                    goal("Sleep (hours)", value: $goals.sleepHours)
                } footer: { Text("Optional personal targets. Blank goals hide target rings. FitOut does not choose health targets for you.") }
                Section("Widgets") {
                    Text("Touch and hold your Home Screen, choose Edit → Add Widget, and search for FitOut. Resize a widget to reveal more actions. Lock Screen widgets are available from Lock Screen customization.")
                }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            .font(FitTheme.body(14)).navigationTitle("Widget goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.saveGoals(goals) { dismiss() } }.disabled(!goals.isValid) }
            }
            .onAppear { goals = store.state.goals }
        }.tint(FitTheme.dashboardAccent)
    }
    private func goal(_ title: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            TextField("Optional", value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
        }
    }
}

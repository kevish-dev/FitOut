import SwiftUI

struct FoodSelectionSheet: View {
    let store: NutritionStore
    var date = Date()
    var meal = NutritionMeal.suggested()
    var ingredientsOnly = false
    var excludingID: String?
    let onSelect: (FoodPortion, Date, NutritionMeal) -> Bool
    @State private var search = ""
    @State private var filter = 0
    @State private var chosen: NutritionFood?
    @State private var custom: NutritionFood?
    @State private var created: NutritionFood?
    @Environment(\.dismiss) private var dismiss
    private var foods: [NutritionFood] {
        let all = filter == 1 ? store.recentFoods : filter == 2 ? store.favoriteFoods : store.foods
        return all.filter { $0.id != excludingID && $0.matches(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Browse", selection: $filter) { Text("All foods").tag(0); Text("Recent").tag(1); Text("Favorites").tag(2) }.pickerStyle(.segmented)
                }
                if foods.isEmpty {
                    ContentUnavailableView("No matching foods", systemImage: "magnifyingglass", description: Text("Try another name or create a food from its label."))
                }
                Section("\(foods.count) foods") {
                    ForEach(foods) { food in
                        HStack(spacing: 8) {
                            Button { chosen = food } label: { NutritionFoodRow(food: food) }.buttonStyle(.fitPlain)
                                .accessibilityIdentifier("selectFood-\(food.id)")
                            Button { _ = store.favorite(food.id) } label: { Image(systemName: store.preferences.favoriteIDs.contains(food.id) ? "star.fill" : "star").frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.borderless).accessibilityLabel("Favorite \(food.name)")
                        }
                    }
                }
                Section { Text("Reference foods show their preparation and source. Recipe estimates are editable; choose the entry that matches what you ate.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary) }
            }
            .navigationTitle(ingredientsOnly ? "Add ingredient" : "Add food")
            .searchable(text: $search, prompt: "Food, brand or Indian name")
            .nutritionForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("Create food", systemImage: "plus") { custom = NutritionFood(name: search) } }
            }
            .navigationDestination(isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } })) {
                if let food = chosen {
                FoodPortionEditor(store: store, portion: FoodPortion(food: food), date: NutritionDates.timestamp(on: date), meal: meal,
                                  ingredientsOnly: ingredientsOnly, title: ingredientsOnly ? "Ingredient amount" : "Food portion", dismissAfterSave: false) { portion, timestamp, meal, _ in
                    if onSelect(portion, timestamp, meal) { dismiss(); return true }; return false
                }
                }
            }
            .sheet(item: $custom, onDismiss: { if let created { chosen = created }; created = nil }) { food in
                NutritionFoodEditor(store: store, food: food) { created = $0 }
            }
        }
    }
}

struct FoodPortionEditor: View {
    let store: NutritionStore
    @State var portion: FoodPortion
    @State var date: Date
    @State var meal: NutritionMeal
    @State var note = ""
    var ingredientsOnly = false
    var title = "Food portion"
    var dismissAfterSave = true
    let onSave: (FoodPortion, Date, NutritionMeal, String) -> Bool
    @Environment(\.dismiss) private var dismiss
    private var total: NutritionValues { portion.values }
    var body: some View {
        Form {
            Section {
                Text(portion.food.name).font(FitTheme.section(22))
                Text(portion.food.sourceTitle).font(FitTheme.medium(12)).foregroundStyle(FitTheme.dashboardAccent)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(NutritionUI.value(total.calories)).font(FitTheme.metric(32))
                    Text("kcal for this portion").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
            }
            Section("Amount") {
                NutritionNumberField(title: "Quantity", value: Binding(get: { portion.quantity }, set: { portion.quantity = $0 ?? 0 }))
                Picker("Serving", selection: Binding(get: { portion.serving.id }, set: { id in if let value = portion.food.portions.first(where: { $0.id == id }) { portion.serving = value } })) {
                    ForEach(portion.food.portions) { serving in Text(serving.title).tag(serving.id) }
                }
                Text("\(NutritionUI.value(portion.quantity * portion.serving.baseAmount, decimals: 2)) \(portion.food.baseUnit.rawValue) of the listed preparation")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                if !portion.isValid { Text("Enter a positive quantity within the supported range.").foregroundStyle(.orange) }
            }
            if !ingredientsOnly {
                Section("Meal & time") {
                    Picker("Meal", selection: $meal) { ForEach(NutritionMeal.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("Logged at", selection: $date, in: ...Date())
                    TextField("Note (optional)", text: $note, axis: .vertical)
                }
            }
            Section("Nutrition for this portion") { NutritionValuesList(values: total, incomplete: portion.food.incomplete) }
            Section("Source") {
                Text(portion.food.sourceDetail).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                if let source = portion.food.sourceURL, let url = URL(string: source), url.scheme == "https" { Link("View source", destination: url) }
                if portion.food.estimated { Text("This is an estimate. Ingredients, oil, preparation and serving weight can change the result.").font(FitTheme.body(12)).foregroundStyle(.orange) }
            }
            Section {
                DisclosureGroup("Correct nutrition for this entry") {
                    Text("Values below are per \(portion.food.baseQuantity.formatted()) \(portion.food.baseUnit.rawValue). Editing changes this snapshot only.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                    NutritionValueFields(values: Binding(get: { portion.food.values }, set: { values in
                        portion.food.values = values
                        if portion.food.source != .quickAdd { portion.food.source = .custom }
                        portion.food.sourceDetail = "Nutrition adjusted by you for this entry."
                        portion.food.sourceURL = nil; portion.food.incomplete = []
                    }))
                    Toggle("Values are estimated", isOn: $portion.food.estimated)
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.orange) }
        }
        .navigationTitle(title).nutritionForm()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(ingredientsOnly ? "Use ingredient" : "Save") { if onSave(portion, date, meal, note), dismissAfterSave { dismiss() } }
                    .disabled(!portion.isValid || note.count > 1_000).accessibilityIdentifier("saveFoodPortion")
            }
        }
    }
}

struct NutritionFoodEditor: View {
    let store: NutritionStore
    @State var food: NutritionFood
    var onSaved: ((NutritionFood) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Food name", text: $food.name).accessibilityIdentifier("customFoodName")
                    TextField("Brand (optional)", text: $food.brand)
                    TextField("Aliases (optional)", text: $food.aliases)
                    TextField("Preparation: raw, cooked…", text: $food.preparation)
                }
                Section("Reference amount") {
                    NutritionNumberField(title: "Quantity", value: Binding(get: { food.baseQuantity }, set: { food.baseQuantity = $0 ?? 0 }))
                    Picker("Unit", selection: $food.baseUnit) { ForEach(FoodBaseUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                Section {
                    NutritionValueFields(values: $food.values)
                    Toggle("Values are estimated", isOn: $food.estimated)
                } header: { Text("Nutrition per reference amount") } footer: { Text("Use the matching pack label or your own calculation. Leave unavailable nutrients blank; a blank value is different from zero.") }
                Section("Named servings") {
                    ForEach($food.servings) { $serving in
                        VStack(spacing: 10) {
                            TextField("Serving name, e.g. piece or bowl", text: $serving.title)
                            NutritionNumberField(title: "Amount in \(food.baseUnit.rawValue)", value: Binding(get: { serving.baseAmount }, set: { serving.baseAmount = $0 ?? 0 }))
                        }
                    }.onDelete { food.servings.remove(atOffsets: $0) }
                    Button("Add named serving", systemImage: "plus") { food.servings.append(FoodServing(title: "", baseAmount: food.baseQuantity)) }
                }
                if let message = food.validationMessage { Text(message).font(FitTheme.body(12)).foregroundStyle(.orange) }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Custom food").nutritionForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        food.source = .custom; food.sourceDetail = "Entered by you"; food.sourceURL = nil
                        if store.saveFood(food) { onSaved?(food); dismiss() }
                    }.disabled(food.validationMessage != nil)
                }
            }
        }
    }
}

struct NutritionQuickAddView: View {
    let store: NutritionStore
    @State var date: Date
    @State var meal: NutritionMeal
    @State private var name = "Quick add"
    @State private var values = NutritionValues()
    @State private var estimated = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Entry name", text: $name)
                    Picker("Meal", selection: $meal) { ForEach(NutritionMeal.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("Logged at", selection: $date, in: ...Date())
                }
                Section { NutritionValueFields(values: $values); Toggle("Totals are estimated", isOn: $estimated) } header: { Text("Totals for the whole entry") } footer: {
                    Text("Manual totals, not a database food. Calories are required; macros and other nutrients may remain blank. Energy is not forced to match a 4/4/9 calculation.")
                }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Quick add").nutritionForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log totals") {
                        let food = NutritionFood(name: name, baseQuantity: 1, baseUnit: .serving, values: values, source: .quickAdd, sourceDetail: "Manual totals entered by you; not a verified database food.", estimated: estimated)
                        if store.saveEntry(FoodLogEntry(date: date, meal: meal, portion: FoodPortion(food: food))) { dismiss() }
                    }.disabled(values.calories == nil || !values.isValid || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { date = NutritionDates.timestamp(on: date) }
        }
    }
}

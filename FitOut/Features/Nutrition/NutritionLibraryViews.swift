import SwiftUI

struct NutritionLibraryView: View {
    let store: NutritionStore
    let date: Date
    @State private var section = 0
    @State private var search = ""
    @State private var custom: NutritionFood?
    @State private var recipe: NutritionRecipe?
    @State private var saved: NutritionSavedMeal?
    @State private var loggingFood: NutritionFood?
    @State private var loggingMeal: NutritionSavedMeal?
    @State private var meal = NutritionMeal.suggested()
    @State private var deletingFood: NutritionFood?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Picker("Library", selection: $section) { Text("Foods").tag(0); Text("Recipes").tag(1); Text("Meals").tag(2) }.pickerStyle(.segmented)
                if section == 0 {
                    ForEach(store.foods.filter { $0.source != .recipe && $0.matches(search) }) { food in
                        HStack {
                            Button { loggingFood = food } label: { NutritionFoodRow(food: food) }.buttonStyle(.plain)
                            Menu {
                                Button(store.preferences.favoriteIDs.contains(food.id) ? "Unfavorite" : "Favorite") { _ = store.favorite(food.id) }
                                if food.source == .custom {
                                    Button("Edit food") { custom = food }
                                    Button("Delete custom food", role: .destructive) { deletingFood = food }
                                } else {
                                    Button("Make an editable copy") { var copy = food; copy.id = UUID().uuidString; copy.source = .custom; custom = copy }
                                }
                            } label: { Image(systemName: "ellipsis").frame(width: 36, height: 44) }.accessibilityLabel("Options for \(food.name)")
                        }
                    }
                } else if section == 1 {
                    if store.recipes.isEmpty { ContentUnavailableView("Your recipes", systemImage: "book.closed", description: Text("Combine ingredients once, then log by serving or finished weight.")) }
                    ForEach(store.recipes.filter { $0.name.localizedCaseInsensitiveContains(search) || search.isEmpty }) { item in
                        Button { loggingFood = item.food } label: {
                            NutritionFoodRow(food: item.food)
                        }.buttonStyle(.plain).contextMenu {
                            Button("Edit recipe") { recipe = item }
                            Button("Delete recipe", role: .destructive) { _ = store.deleteRecipe(item.id) }
                        }
                        .swipeActions { Button("Edit") { recipe = item }; Button("Delete", role: .destructive) { _ = store.deleteRecipe(item.id) } }
                    }
                } else {
                    if store.savedMeals.isEmpty { ContentUnavailableView("Meals worth repeating", systemImage: "square.stack", description: Text("Save a meal from your diary, or build a combination here.")) }
                    ForEach(store.savedMeals.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in
                        Button { loggingMeal = item } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name).font(FitTheme.section(16))
                                Text("\(item.items.count) foods · \(NutritionUI.value(NutritionValues.sum(item.items.map(\.values)).calories)) kcal")
                                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain).contextMenu {
                            Button("Edit saved meal") { saved = item }
                            Button("Delete saved meal", role: .destructive) { _ = store.deleteMeal(item.id) }
                        }
                        .swipeActions { Button("Edit") { saved = item }; Button("Delete", role: .destructive) { _ = store.deleteMeal(item.id) } }
                    }
                }
                Text("Editing or deleting a library item keeps the snapshots in past food logs unchanged.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Your food library").searchable(text: $search).nutritionForm()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Create", systemImage: "plus") {
                        Button("Custom food") { custom = NutritionFood(name: "") }
                        Button("Recipe") { recipe = NutritionRecipe() }
                        Button("Saved meal") { saved = NutritionSavedMeal() }
                    }
                }
            }
            .sheet(item: $custom) { NutritionFoodEditor(store: store, food: $0) }
            .sheet(item: $recipe) { NutritionRecipeEditor(store: store, recipe: $0) }
            .sheet(item: $saved) { NutritionSavedMealEditor(store: store, meal: $0) }
            .sheet(item: $loggingFood) { food in
                NavigationStack { FoodPortionEditor(store: store, portion: FoodPortion(food: food), date: NutritionDates.timestamp(on: date), meal: meal) { portion, timestamp, chosenMeal, note in store.saveEntry(FoodLogEntry(date: timestamp, meal: chosenMeal, portion: portion, note: note)) } }
            }
            .sheet(item: $loggingMeal) { item in
                NavigationStack {
                    Form {
                        Section(item.name) {
                            ForEach(item.items) { portion in Text("\(portion.food.name) · \(portion.label)") }
                            Picker("Log to", selection: $meal) { ForEach(NutritionMeal.allCases) { Text($0.rawValue).tag($0) } }
                            Text(date.formatted(date: .complete, time: .omitted)).foregroundStyle(.secondary)
                        }
                        if let error = store.error { Text(error).foregroundStyle(.orange) }
                    }.nutritionForm().navigationTitle("Log saved meal").toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { loggingMeal = nil } }
                        ToolbarItem(placement: .confirmationAction) { Button("Log \(item.items.count) foods") { if store.logMeal(item, on: date, meal: meal) { loggingMeal = nil } } }
                    }
                }
            }
            .confirmationDialog("Delete custom food?", isPresented: Binding(get: { deletingFood != nil }, set: { if !$0 { deletingFood = nil } }), titleVisibility: .visible) {
                Button("Delete food", role: .destructive) { if let deletingFood { _ = store.deleteFood(deletingFood.id) }; deletingFood = nil }
            } message: { Text("Past logs and saved ingredient snapshots stay unchanged.") }
        }
    }
}

struct NutritionRecipeEditor: View {
    let store: NutritionStore
    @State var recipe: NutritionRecipe
    @State private var adding = false
    @State private var editing: FoodPortion?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Recipe name", text: $recipe.name)
                    NutritionNumberField(title: "Number of servings", value: Binding(get: { recipe.yieldServings }, set: { recipe.yieldServings = $0 ?? 0 }))
                    NutritionNumberField(title: "Finished weight (g, optional)", value: $recipe.yieldGrams)
                }
                Section {
                    ForEach(recipe.ingredients) { ingredient in
                        Button { editing = ingredient } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(ingredient.food.name).font(FitTheme.medium(15))
                                Text("\(ingredient.label) · \(NutritionUI.value(ingredient.values.calories)) kcal").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }.foregroundStyle(FitTheme.textPrimary).padding(.vertical, 4)
                        }
                    }.onDelete { recipe.ingredients.remove(atOffsets: $0) }
                    Button("Add ingredient", systemImage: "plus") { adding = true }
                } header: { Text("Ingredients") } footer: { Text("Choose raw or cooked ingredient records as weighed. Final cooked weight enables logging the finished recipe in grams.") }
                if !recipe.ingredients.isEmpty {
                    Section("Per recipe serving") { NutritionValuesList(values: recipe.food.values, incomplete: recipe.food.incomplete) }
                    Text("Recipe values depend on the ingredient records. Missing nutrients stay marked as partial. Editing this recipe does not rewrite previous logs.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
                if let message = recipe.validationMessage { Text(message).font(FitTheme.body(12)).foregroundStyle(.orange) }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.nutritionForm().navigationTitle("Recipe builder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save recipe") { if store.saveRecipe(recipe) { dismiss() } }.disabled(recipe.validationMessage != nil) }
            }
            .sheet(isPresented: $adding) {
                FoodSelectionSheet(store: store, ingredientsOnly: true, excludingID: recipe.food.id) { portion, _, _ in recipe.ingredients.append(portion.independentCopy()); return true }
            }
            .sheet(item: $editing) { portion in
                NavigationStack {
                    FoodPortionEditor(store: store, portion: portion, date: .now, meal: .lunch, ingredientsOnly: true) { value, _, _, _ in
                        if let index = recipe.ingredients.firstIndex(where: { $0.id == portion.id }) { recipe.ingredients[index] = value }
                        return true
                    }
                }
            }
        }
    }
}

struct NutritionSavedMealEditor: View {
    let store: NutritionStore
    @State var meal: NutritionSavedMeal
    @State private var adding = false
    @State private var editing: FoodPortion?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Meal name", text: $meal.name) }
                Section("Foods & portions") {
                    ForEach(meal.items) { item in
                        Button { editing = item } label: {
                            VStack(alignment: .leading, spacing: 5) { Text(item.food.name); Text(item.label).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary) }.foregroundStyle(FitTheme.textPrimary)
                        }
                    }.onDelete { meal.items.remove(atOffsets: $0) }
                    Button("Add food", systemImage: "plus") { adding = true }
                }
                Section("Whole meal") { NutritionValuesList(values: NutritionValues.sum(meal.items.map(\.values)), incomplete: NutritionNutrient.allCases.filter { key in meal.items.contains { $0.food.values[key] == nil || $0.food.incomplete.contains(key) } }) }
                Text("Logging this meal creates individual food entries. Each entry can then be edited or moved independently.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.nutritionForm().navigationTitle("Reusable meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save meal") { if store.saveMeal(meal) { dismiss() } }.disabled(!meal.isValid) }
            }
            .sheet(isPresented: $adding) { FoodSelectionSheet(store: store, ingredientsOnly: true) { portion, _, _ in meal.items.append(portion.independentCopy()); return true } }
            .sheet(item: $editing) { portion in
                NavigationStack { FoodPortionEditor(store: store, portion: portion, date: .now, meal: .lunch, ingredientsOnly: true) { value, _, _, _ in
                    if let index = meal.items.firstIndex(where: { $0.id == portion.id }) { meal.items[index] = value }; return true
                } }
            }
        }
    }
}

struct NutritionCopyMealView: View {
    let store: NutritionStore
    let destination: Date
    @State private var source = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
    @State private var fromMeal = NutritionMeal.dinner
    @State private var toMeal = NutritionMeal.dinner
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Copy from") {
                    DatePicker("Date", selection: $source, in: ...Date(), displayedComponents: .date)
                    Picker("Meal", selection: $fromMeal) { ForEach(NutritionMeal.allCases) { Text($0.rawValue).tag($0) } }
                    ForEach(store.entries(on: source, meal: fromMeal)) { entry in Text("\(entry.portion.food.name) · \(entry.portion.label)") }
                    if store.entries(on: source, meal: fromMeal).isEmpty { Text("No foods logged for this meal.").foregroundStyle(.secondary) }
                }
                Section("Copy to") {
                    Text(destination.formatted(date: .complete, time: .omitted))
                    Picker("Meal", selection: $toMeal) { ForEach(NutritionMeal.allCases) { Text($0.rawValue).tag($0) } }
                    Text("Adds new entries. Existing entries in the destination meal are kept.").font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.nutritionForm().navigationTitle("Copy a meal")
            .onAppear { source = Calendar.current.date(byAdding: .day, value: -1, to: destination) ?? destination }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy \(store.entries(on: source, meal: fromMeal).count) foods") { if store.copyMeal(from: source, meal: fromMeal, to: destination, destinationMeal: toMeal) { dismiss() } }.disabled(store.entries(on: source, meal: fromMeal).isEmpty)
                }
            }
        }
    }
}

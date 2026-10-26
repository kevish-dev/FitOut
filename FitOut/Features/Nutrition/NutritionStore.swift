import Foundation
import SwiftData
import Observation

enum NutritionCatalogue {
    static func load(bundle: Bundle = .main) throws -> [NutritionFood] {
        guard let url = bundle.url(forResource: "NutritionFoods", withExtension: "json") else { throw NutritionFailure.invalid("The offline food library is missing from the app bundle.") }
        let foods = try JSONDecoder().decode([NutritionFood].self, from: Data(contentsOf: url))
        guard !foods.isEmpty, Set(foods.map(\.id)).count == foods.count, foods.allSatisfy({ $0.validationMessage == nil }) else { throw NutritionFailure.invalid("The offline food library could not be validated.") }
        return foods
    }
}

@MainActor @Observable final class NutritionStore {
    private let context: ModelContext
    private let catalogue: [NutritionFood]
    private(set) var customFoods: [NutritionFood] = []
    private(set) var entries: [FoodLogEntry] = []
    private(set) var recipes: [NutritionRecipe] = []
    private(set) var savedMeals: [NutritionSavedMeal] = []
    private(set) var targets: [NutritionTarget] = []
    private(set) var preferences = NutritionPreferences()
    var error: String?
    var deletedEntry: FoodLogEntry?
    var onChange: (() -> Void)?
    var onFeedback: ((FitHapticEvent) -> Void)?
    init(container: ModelContainer, catalogue: [NutritionFood]? = nil) throws {
        context = ModelContext(container); context.autosaveEnabled = false
        self.catalogue = try catalogue ?? NutritionCatalogue.load()
        try reload()
    }
    var foods: [NutritionFood] { (catalogue + customFoods + recipes.map(\.food)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var recentFoods: [NutritionFood] {
        let current = foods
        var seen = Set<String>()
        var recent: [NutritionFood] = []
        for entry in entries where entry.portion.food.source != .quickAdd {
            guard seen.insert(entry.portion.food.id).inserted else { continue }
            recent.append(current.first { $0.id == entry.portion.food.id } ?? entry.portion.food)
            if recent.count == 20 { break }
        }
        return recent
    }
    var favoriteFoods: [NutritionFood] {
        preferences.favoriteIDs.compactMap { id in foods.first { $0.id == id } ?? entries.first { $0.portion.food.id == id }?.portion.food }.sorted { $0.name < $1.name }
    }
    func entries(on date: Date, meal: NutritionMeal? = nil, calendar: Calendar = .current) -> [FoodLogEntry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: date) && (meal == nil || $0.meal == meal) }.sorted { $0.date < $1.date }
    }
    func summary(on date: Date, calendar: Calendar = .current) -> NutritionDaySummary { NutritionDaySummary(entries: entries(on: date, calendar: calendar)) }
    func target(on date: Date, calendar: Calendar = .current) -> NutritionValues {
        let day = calendar.startOfDay(for: date)
        return targets.filter { calendar.startOfDay(for: $0.effectiveDate) <= day }.max { $0.effectiveDate < $1.effectiveDate }?.values ?? NutritionValues()
    }
    func reload() throws {
        let decoder = JSONDecoder()
        customFoods = try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodRecord>()).map { try decoder.decode(NutritionFood.self, from: $0.payload) }
        entries = try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodEntryRecord>()).map { try decoder.decode(FoodLogEntry.self, from: $0.payload) }.sorted { $0.date > $1.date }
        recipes = try context.fetch(FetchDescriptor<FitOutSchemaV6.RecipeRecord>()).map { try decoder.decode(NutritionRecipe.self, from: $0.payload) }.sorted { $0.name < $1.name }
        savedMeals = try context.fetch(FetchDescriptor<FitOutSchemaV6.SavedMealRecord>()).map { try decoder.decode(NutritionSavedMeal.self, from: $0.payload) }.sorted { $0.name < $1.name }
        targets = try context.fetch(FetchDescriptor<FitOutSchemaV6.TargetRecord>()).map { try decoder.decode(NutritionTarget.self, from: $0.payload) }
        if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.NutritionSettingsRecord>()).first { preferences = try decoder.decode(NutritionPreferences.self, from: record.payload) }
        else { preferences = NutritionPreferences() }
    }
    @discardableResult func saveFood(_ input: NutritionFood) -> Bool {
        transact {
            if let message = input.validationMessage { throw NutritionFailure.invalid(message) }
            guard input.source == .custom, !input.id.hasPrefix("recipe-"), !catalogue.contains(where: { $0.id == input.id }) else { throw NutritionFailure.invalid("Make a custom copy to edit a reference food.") }
            var food = input; food.name = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let data = try JSONEncoder().encode(food)
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodRecord>()).first(where: { $0.id == food.id }) { record.payload = data }
            else { context.insert(FitOutSchemaV6.FoodRecord(id: food.id, payload: data)) }
        }
    }
    @discardableResult func deleteFood(_ id: String) -> Bool {
        transact {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodRecord>()).first(where: { $0.id == id }) { context.delete(record) }
            var prefs = preferences; prefs.favoriteIDs.remove(id); try writePreferences(prefs)
        }
    }
    @discardableResult func favorite(_ id: String) -> Bool {
        transact(feedback: .selection) {
            var value = preferences
            if value.favoriteIDs.contains(id) { value.favoriteIDs.remove(id) } else { value.favoriteIDs.insert(id) }
            try writePreferences(value)
        }
    }
    @discardableResult func saveEntry(_ entry: FoodLogEntry) -> Bool { saveEntries([entry]) }
    @discardableResult func saveEntries(_ inputs: [FoodLogEntry]) -> Bool {
        transact {
            guard !inputs.isEmpty, inputs.allSatisfy(\.isValid), Set(inputs.map(\.id)).count == inputs.count else { throw NutritionFailure.invalid("Check the food values, portion and date. Future entries are not supported.") }
            let existing = try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodEntryRecord>())
            for entry in inputs {
                let payload = try JSONEncoder().encode(entry)
                if let record = existing.first(where: { $0.id == entry.id }) { record.date = entry.date; record.payload = payload }
                else { context.insert(FitOutSchemaV6.FoodEntryRecord(id: entry.id, date: entry.date, payload: payload)) }
            }
        }
    }
    @discardableResult func deleteEntry(_ entry: FoodLogEntry) -> Bool {
        let result = transact {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodEntryRecord>()).first(where: { $0.id == entry.id }) { context.delete(record) }
        }
        if result { deletedEntry = entry }
        return result
    }
    func undoDelete() { if let deletedEntry, saveEntry(deletedEntry) { self.deletedEntry = nil } }
    @discardableResult func repeatEntry(_ entry: FoodLogEntry, on date: Date, meal: NutritionMeal? = nil) -> Bool {
        var copy = entry; copy.id = UUID(); copy.date = NutritionDates.timestamp(on: date); copy.meal = meal ?? entry.meal
        return saveEntry(copy)
    }
    @discardableResult func copyMeal(from date: Date, meal: NutritionMeal, to destination: Date, destinationMeal: NutritionMeal) -> Bool {
        let copies = entries(on: date, meal: meal).map { entry in
            var copy = entry; copy.id = UUID(); copy.date = NutritionDates.timestamp(on: destination, time: entry.date); copy.meal = destinationMeal; return copy
        }
        return saveEntries(copies)
    }
    @discardableResult func saveRecipe(_ value: NutritionRecipe) -> Bool {
        transact {
            if let message = value.validationMessage { throw NutritionFailure.invalid(message) }
            guard value.food.validationMessage == nil else { throw NutritionFailure.invalid("The recipe's calculated nutrition exceeds supported values.") }
            let payload = try JSONEncoder().encode(value)
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.RecipeRecord>()).first(where: { $0.id == value.id }) { record.payload = payload }
            else { context.insert(FitOutSchemaV6.RecipeRecord(id: value.id, payload: payload)) }
        }
    }
    @discardableResult func deleteRecipe(_ id: UUID) -> Bool {
        transact {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.RecipeRecord>()).first(where: { $0.id == id }) { context.delete(record) }
            var prefs = preferences; prefs.favoriteIDs.remove("recipe-" + id.uuidString); try writePreferences(prefs)
        }
    }
    @discardableResult func saveMeal(_ value: NutritionSavedMeal) -> Bool {
        transact {
            guard value.isValid else { throw NutritionFailure.invalid("Name the meal and add at least one valid food portion.") }
            let payload = try JSONEncoder().encode(value)
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.SavedMealRecord>()).first(where: { $0.id == value.id }) { record.payload = payload }
            else { context.insert(FitOutSchemaV6.SavedMealRecord(id: value.id, payload: payload)) }
        }
    }
    @discardableResult func deleteMeal(_ id: UUID) -> Bool {
        transact { if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.SavedMealRecord>()).first(where: { $0.id == id }) { context.delete(record) } }
    }
    @discardableResult func logMeal(_ saved: NutritionSavedMeal, on date: Date, meal: NutritionMeal) -> Bool {
        saveEntries(saved.items.map { FoodLogEntry(date: NutritionDates.timestamp(on: date), meal: meal, portion: $0.independentCopy()) })
    }
    @discardableResult func saveTarget(_ values: NutritionValues, from date: Date, calendar: Calendar = .current) -> Bool {
        transact {
            let day = calendar.startOfDay(for: date)
            guard NutritionTarget(effectiveDate: day, values: values).isValid else { throw NutritionFailure.invalid("Targets must be positive, or left blank.") }
            let existing = try context.fetch(FetchDescriptor<FitOutSchemaV6.TargetRecord>())
            let record = try existing.first { try calendar.isDate(JSONDecoder().decode(NutritionTarget.self, from: $0.payload).effectiveDate, inSameDayAs: day) }
            let target = NutritionTarget(id: record?.id ?? UUID(), effectiveDate: day, values: values)
            let payload = try JSONEncoder().encode(target)
            if let record { record.payload = payload } else { context.insert(FitOutSchemaV6.TargetRecord(id: target.id, payload: payload)) }
        }
    }
    @discardableResult func deleteAllNutrition() -> Bool {
        let result = transact {
            for record in try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodRecord>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<FitOutSchemaV6.FoodEntryRecord>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<FitOutSchemaV6.RecipeRecord>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<FitOutSchemaV6.SavedMealRecord>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<FitOutSchemaV6.TargetRecord>()) { context.delete(record) }
            for record in try context.fetch(FetchDescriptor<FitOutSchemaV6.NutritionSettingsRecord>()) { context.delete(record) }
        }
        if result { deletedEntry = nil }
        return result
    }
    private func writePreferences(_ value: NutritionPreferences) throws {
        let data = try JSONEncoder().encode(value)
        if let record = try context.fetch(FetchDescriptor<FitOutSchemaV6.NutritionSettingsRecord>()).first { record.payload = data }
        else { context.insert(FitOutSchemaV6.NutritionSettingsRecord(payload: data)) }
    }
    private func transact(feedback: FitHapticEvent = .saved, _ action: () throws -> Void) -> Bool {
        do { try action(); try context.save(); try reload(); error = nil; onChange?(); onFeedback?(feedback); return true }
        catch { context.rollback(); self.error = error.localizedDescription; onFeedback?(.warning); return false }
    }
}

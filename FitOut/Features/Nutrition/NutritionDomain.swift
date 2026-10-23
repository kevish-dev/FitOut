import Foundation

enum NutritionNutrient: String, Codable, CaseIterable, Identifiable, Sendable {
    case calories, protein, carbohydrates, fat, fibre, sugar, saturatedFat, sodium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .calories: "Calories"
        case .carbohydrates: "Carbohydrates"
        case .saturatedFat: "Saturated fat"
        default: rawValue.capitalized
        }
    }
    var unit: String { self == .calories ? "kcal" : self == .sodium ? "mg" : "g" }
    var maximum: Double { self == .calories ? 100_000 : self == .sodium ? 100_000 : 10_000 }
}

struct NutritionValues: Codable, Equatable, Sendable {
    var calories: Double?
    var protein: Double?
    var carbohydrates: Double?
    var fat: Double?
    var fibre: Double?
    var sugar: Double?
    var saturatedFat: Double?
    var sodium: Double?
    subscript(_ key: NutritionNutrient) -> Double? {
        get {
            switch key {
            case .calories: calories
            case .protein: protein
            case .carbohydrates: carbohydrates
            case .fat: fat
            case .fibre: fibre
            case .sugar: sugar
            case .saturatedFat: saturatedFat
            case .sodium: sodium
            }
        }
        set {
            switch key {
            case .calories: calories = newValue
            case .protein: protein = newValue
            case .carbohydrates: carbohydrates = newValue
            case .fat: fat = newValue
            case .fibre: fibre = newValue
            case .sugar: sugar = newValue
            case .saturatedFat: saturatedFat = newValue
            case .sodium: sodium = newValue
            }
        }
    }
    var isValid: Bool { NutritionNutrient.allCases.allSatisfy { key in self[key].map { $0.isFinite && (0...key.maximum).contains($0) } ?? true } }
    var hasValue: Bool { NutritionNutrient.allCases.contains { self[$0] != nil } }
    func scaled(by factor: Double) -> Self {
        var result = Self()
        for key in NutritionNutrient.allCases { result[key] = self[key].map { $0 * factor } }
        return result
    }
    static func sum(_ values: [Self]) -> Self {
        var result = Self()
        for key in NutritionNutrient.allCases {
            let known = values.compactMap { $0[key] }
            result[key] = known.isEmpty ? nil : known.reduce(0, +)
        }
        return result
    }
}
enum NutritionMeal: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast = "Breakfast", lunch = "Lunch", dinner = "Dinner", snacks = "Snacks"
    var id: String { rawValue }
    var symbol: String { switch self { case .breakfast: "sunrise"; case .lunch: "sun.max"; case .dinner: "moon"; case .snacks: "carrot" } }
    static func suggested(at date: Date = .now, calendar: Calendar = .current) -> Self {
        switch calendar.component(.hour, from: date) { case 5..<11: .breakfast; case 11..<16: .lunch; case 16..<22: .dinner; default: .snacks }
    }
}
enum FoodSource: String, Codable, Sendable { case reference, label, estimate, custom, recipe, quickAdd }
enum FoodBaseUnit: String, Codable, CaseIterable, Sendable { case grams = "g", milliliters = "ml", serving = "serving" }
struct FoodServing: Identifiable, Codable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var title: String
    var baseAmount: Double
    var isValid: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty && baseAmount.isFinite && baseAmount > 0 && baseAmount <= 100_000 }
}
struct NutritionFood: Identifiable, Codable, Equatable, Sendable {
    var id = UUID().uuidString
    var name: String
    var aliases = ""
    var brand = ""
    var baseQuantity = 100.0
    var baseUnit: FoodBaseUnit = .grams
    var values = NutritionValues()
    var servings: [FoodServing] = []
    var source: FoodSource = .custom
    var sourceDetail = "Entered by you"
    var sourceURL: String?
    var incomplete: [NutritionNutrient] = []
    var estimated = false
    var preparation = ""
    var sourceTitle: String {
        switch source {
        case .reference: "USDA reference"
        case .label: "Published product label"
        case .estimate: "Recipe estimate"
        case .custom: "Entered by you"
        case .recipe: estimated ? "Your recipe · estimated" : "Your recipe"
        case .quickAdd: "Manual totals"
        }
    }
    var portions: [FoodServing] {
        [FoodServing(id: "base", title: "\(baseQuantity.formatted()) \(baseUnit.rawValue)", baseAmount: baseQuantity)]
        + (baseUnit == .serving ? [] : [FoodServing(id: "single-unit", title: baseUnit.rawValue, baseAmount: 1)]) + servings
    }
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 100 { return "Enter a food name with 1–100 characters." }
        if !baseQuantity.isFinite || !(0.001...100_000).contains(baseQuantity) { return "Enter a positive reference serving." }
        if !values.isValid || !values.hasValue { return "Enter at least one nutrient value. Values must be finite and nonnegative." }
        if source == .quickAdd && values.calories == nil { return "Quick-add totals need a calorie value." }
        if !servings.allSatisfy(\.isValid) || Set(servings.map(\.id)).count != servings.count || servings.contains(where: { ["base", "single-unit"].contains($0.id) }) { return "Check the named serving amounts." }
        return nil
    }
    func matches(_ search: String) -> Bool {
        let text = (name + " " + aliases + " " + brand + " " + preparation).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return search.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }
}
struct FoodPortion: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var food: NutritionFood
    var serving: FoodServing
    var quantity = 1.0
    init(food: NutritionFood, serving: FoodServing? = nil, quantity: Double = 1) {
        self.food = food; self.serving = serving ?? food.portions[0]; self.quantity = quantity
    }
    var values: NutritionValues { food.values.scaled(by: quantity * serving.baseAmount / food.baseQuantity) }
    var label: String { "\(quantity.formatted(.number.precision(.fractionLength(0...2)))) × \(serving.title)" }
    var isValid: Bool { food.validationMessage == nil && serving.isValid && quantity.isFinite && (0.001...10_000).contains(quantity) && values.isValid }
    func independentCopy() -> Self { var copy = self; copy.id = UUID(); return copy }
}
struct FoodLogEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var date: Date
    var meal: NutritionMeal
    var portion: FoodPortion
    var note = ""
    var isValid: Bool { portion.isValid && date <= Date().addingTimeInterval(60) && note.count <= 1_000 }
}
struct NutritionRecipe: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var ingredients: [FoodPortion] = []
    var yieldServings = 1.0
    var yieldGrams: Double?
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Name your recipe." }
        if ingredients.isEmpty || !ingredients.allSatisfy(\.isValid) { return "Add ingredients with valid amounts." }
        if !yieldServings.isFinite || !(0.01...10_000).contains(yieldServings) { return "Enter a positive number of recipe servings." }
        if let yieldGrams, !yieldGrams.isFinite || !(1...100_000).contains(yieldGrams) { return "Enter a valid final cooked weight, or leave it blank." }
        return nil
    }
    var food: NutritionFood {
        let sums = NutritionValues.sum(ingredients.map(\.values))
        let missing = NutritionNutrient.allCases.filter { key in ingredients.contains { $0.food.values[key] == nil || $0.food.incomplete.contains(key) } }
        var portions = [FoodServing(id: "whole-recipe", title: "whole recipe", baseAmount: yieldServings)]
        if let yieldGrams, yieldGrams > 0 { portions.append(FoodServing(id: "recipe-gram", title: "g of finished recipe", baseAmount: yieldServings / yieldGrams)) }
        return NutritionFood(id: "recipe-" + id.uuidString, name: name, baseQuantity: 1, baseUnit: .serving,
            values: sums.scaled(by: 1 / max(0.01, yieldServings)), servings: portions, source: .recipe,
            sourceDetail: "Calculated from saved ingredient snapshots. Missing ingredient nutrients remain incomplete.",
            incomplete: missing, estimated: ingredients.contains { $0.food.estimated })
    }
}
struct NutritionSavedMeal: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name = ""
    var items: [FoodPortion] = []
    var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty && items.allSatisfy(\.isValid) }
}
struct NutritionTarget: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var effectiveDate: Date
    var values = NutritionValues()
    var isValid: Bool { values.isValid && NutritionNutrient.allCases.allSatisfy { values[$0].map { $0 > 0 } ?? true } }
}
struct NutritionPreferences: Codable, Equatable {
    var favoriteIDs: Set<String> = []
}
struct NutritionDaySummary {
    let entries: [FoodLogEntry]
    var values: NutritionValues { NutritionValues.sum(entries.map { $0.portion.values }) }
    func knownCount(_ key: NutritionNutrient) -> Int { entries.filter { $0.portion.values[key] != nil && !$0.portion.food.incomplete.contains(key) }.count }
    func isComplete(_ key: NutritionNutrient) -> Bool { !entries.isEmpty && knownCount(key) == entries.count }
    var estimateCount: Int { entries.filter { $0.portion.food.estimated }.count }
}
enum NutritionDates {
    static func timestamp(on date: Date, time: Date = .now, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
        let combined = calendar.date(bySettingHour: parts.hour ?? 12, minute: parts.minute ?? 0, second: parts.second ?? 0, of: date) ?? date
        return min(.now, combined)
    }
}
enum NutritionFailure: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { "Nutrition data could not be saved." } }
}

/// A future verified provider can implement search without changing offline logging.
protocol NutritionFoodSearching {
    func search(_ text: String) async throws -> [NutritionFood]
}

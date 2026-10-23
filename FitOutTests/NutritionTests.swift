import XCTest
import SwiftData
@testable import FitOut

final class NutritionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private func date(_ day: Int, hour: Int = 12) -> Date { calendar.date(from: DateComponents(year: 2026, month: 5, day: day, hour: hour))! }
    private var rice: NutritionFood {
        NutritionFood(id: "test-rice", name: "Cooked rice", values: NutritionValues(calories: 130, protein: 2.7, carbohydrates: 28.2, fat: 0.3), servings: [FoodServing(id: "cup", title: "cup (158 g)", baseAmount: 158)], source: .reference)
    }
    func testPortionsScaleGramsNamedServingsAndFractionalQuantities() {
        let grams = FoodPortion(food: rice, serving: rice.portions.first { $0.id == "single-unit" }, quantity: 150)
        XCTAssertEqual(grams.values.calories!, 195, accuracy: 0.0001)
        XCTAssertEqual(grams.values.protein!, 4.05, accuracy: 0.0001)
        let cup = FoodPortion(food: rice, serving: rice.servings[0], quantity: 0.5)
        XCTAssertEqual(cup.values.calories!, 102.7, accuracy: 0.0001)
        XCTAssertNil(cup.values.sodium)
        var invalid = cup; invalid.quantity = .nan; XCTAssertFalse(invalid.isValid)
        invalid.quantity = -1; XCTAssertFalse(invalid.isValid)
        XCTAssertFalse(rice.portions.contains { $0.title == "ml" })
    }
    func testMissingValuesRemainUnknownAndPartialTotalsAreExplicit() {
        let food = NutritionFood(name: "Manual food", values: NutritionValues(calories: 50))
        let entries = [FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: rice)), FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: food))]
        let summary = NutritionDaySummary(entries: entries)
        XCTAssertEqual(summary.values.calories, 180)
        XCTAssertEqual(summary.values.protein, 2.7)
        XCTAssertNil(summary.values.fibre)
        XCTAssertTrue(summary.isComplete(.calories))
        XCTAssertFalse(summary.isComplete(.protein))
        XCTAssertEqual(summary.knownCount(.protein), 1)
        XCTAssertNil(NutritionDaySummary(entries: []).values.calories)
        XCTAssertFalse(NutritionDaySummary(entries: []).isComplete(.calories))
    }
    func testRecipeYieldAndCookedWeightUseIngredientSnapshots() throws {
        let paneer = NutritionFood(name: "Label paneer", values: NutritionValues(calories: 312, protein: 20, carbohydrates: 4, fat: 24), source: .label)
        let recipe = NutritionRecipe(name: "Rice bowl", ingredients: [FoodPortion(food: rice, quantity: 2), FoodPortion(food: paneer)], yieldServings: 2, yieldGrams: 500)
        XCTAssertNil(recipe.validationMessage)
        XCTAssertEqual(recipe.food.values.calories!, 286, accuracy: 0.0001)
        XCTAssertEqual(recipe.food.values.protein!, 12.7, accuracy: 0.0001)
        let byWeight = FoodPortion(food: recipe.food, serving: try XCTUnwrap(recipe.food.servings.first { $0.id == "recipe-gram" }), quantity: 250)
        XCTAssertEqual(byWeight.values.calories!, 286, accuracy: 0.0001)
        XCTAssertNil(recipe.food.values.fibre)
        XCTAssertTrue(recipe.food.incomplete.contains(.fibre))
        var incomplete = recipe
        incomplete.ingredients[1].food.values.protein = nil
        XCTAssertEqual(incomplete.food.values.protein!, 2.7, accuracy: 0.0001)
        XCTAssertTrue(incomplete.food.incomplete.contains(.protein))
        var invalid = recipe; invalid.yieldServings = 0; XCTAssertNotNil(invalid.validationMessage)
    }
    @MainActor func testFoodEditsAndDeletionNeverRewriteHistoryAndReopenPreservesData() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try NutritionStore(container: container, catalogue: [rice])
        var custom = NutritionFood(name: "My cereal", values: NutritionValues(calories: 200, protein: 8))
        XCTAssertTrue(store.saveFood(custom))
        let entry = FoodLogEntry(date: date(7), meal: .breakfast, portion: FoodPortion(food: custom, quantity: 1.5))
        XCTAssertTrue(store.saveEntry(entry))
        custom.values.calories = 500; XCTAssertTrue(store.saveFood(custom))
        XCTAssertEqual(store.entries[0].portion.values.calories, 300)
        XCTAssertTrue(store.favorite(custom.id))
        let reopened = try NutritionStore(container: container, catalogue: [rice])
        XCTAssertEqual(reopened.entries[0], entry)
        XCTAssertTrue(reopened.preferences.favoriteIDs.contains(custom.id))
        XCTAssertTrue(reopened.deleteFood(custom.id))
        XCTAssertEqual(reopened.entries[0].portion.values.calories, 300)
        XCTAssertTrue(reopened.repeatEntry(entry, on: date(8)))
        XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertEqual(Set(reopened.entries.map(\.id)).count, 2)
    }
    @MainActor func testEntryEditingMovingDeletingAndUndoRetainTimestamps() throws {
        let store = try NutritionStore(container: PersistenceFactory.makeContainer(inMemory: true), catalogue: [rice])
        var entry = FoodLogEntry(date: date(7, hour: 8), meal: .breakfast, portion: FoodPortion(food: rice))
        XCTAssertTrue(store.saveEntry(entry))
        entry.meal = .lunch; entry.portion.quantity = 1.5
        XCTAssertTrue(store.saveEntry(entry))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].date, date(7, hour: 8))
        XCTAssertEqual(store.entries[0].portion.values.calories, 195)
        XCTAssertTrue(store.deleteEntry(entry)); XCTAssertTrue(store.entries.isEmpty)
        store.undoDelete(); XCTAssertEqual(store.entries, [entry]); XCTAssertNil(store.deletedEntry)
    }
    @MainActor func testSavedMealsAndRecipesPreserveLoggedSnapshots() throws {
        let store = try NutritionStore(container: PersistenceFactory.makeContainer(inMemory: true), catalogue: [rice])
        var recipe = NutritionRecipe(name: "Rice recipe", ingredients: [FoodPortion(food: rice)], yieldServings: 1)
        XCTAssertTrue(store.saveRecipe(recipe))
        let entry = FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: recipe.food))
        XCTAssertTrue(store.saveEntry(entry))
        recipe.yieldServings = 2; XCTAssertTrue(store.saveRecipe(recipe))
        XCTAssertEqual(store.entries[0].portion.values.calories, 130)
        XCTAssertTrue(store.deleteRecipe(recipe.id)); XCTAssertEqual(store.entries[0].portion.values.calories, 130)
        let meal = NutritionSavedMeal(name: "Lunch", items: [FoodPortion(food: rice), FoodPortion(food: rice, quantity: 0.5)])
        XCTAssertTrue(store.saveMeal(meal)); XCTAssertTrue(store.logMeal(meal, on: date(8), meal: .dinner))
        XCTAssertEqual(store.entries(on: date(8)).count, 2)
        XCTAssertEqual(store.summary(on: date(8)).values.calories, 195)
        XCTAssertTrue(store.deleteMeal(meal.id)); XCTAssertEqual(store.entries(on: date(8)).count, 2)
    }
    @MainActor func testTargetVersionsDoNotRewriteEarlierDaysAndCanBeSkipped() throws {
        let store = try NutritionStore(container: PersistenceFactory.makeContainer(inMemory: true), catalogue: [rice])
        XCTAssertNil(store.target(on: date(7), calendar: calendar).calories)
        XCTAssertTrue(store.saveTarget(NutritionValues(calories: 2_000, protein: 100), from: date(7), calendar: calendar))
        XCTAssertTrue(store.saveTarget(NutritionValues(calories: 2_200), from: date(9), calendar: calendar))
        XCTAssertEqual(store.target(on: date(8), calendar: calendar).calories, 2_000)
        XCTAssertEqual(store.target(on: date(10), calendar: calendar).calories, 2_200)
        XCTAssertTrue(store.saveTarget(NutritionValues(), from: date(11), calendar: calendar))
        XCTAssertNil(store.target(on: date(12), calendar: calendar).calories)
        XCTAssertEqual(store.target(on: date(8), calendar: calendar).protein, 100)
        XCTAssertFalse(store.saveTarget(NutritionValues(calories: -1), from: date(7), calendar: calendar))
    }
    @MainActor func testCopyMealCreatesIndependentEntriesAndKeepsDestinationFoods() throws {
        let store = try NutritionStore(container: PersistenceFactory.makeContainer(inMemory: true), catalogue: [rice])
        let source = FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: rice))
        XCTAssertTrue(store.saveEntry(source))
        XCTAssertTrue(store.saveEntry(FoodLogEntry(date: date(8), meal: .dinner, portion: FoodPortion(food: rice))))
        XCTAssertTrue(store.copyMeal(from: date(7), meal: .lunch, to: date(8), destinationMeal: .dinner))
        XCTAssertEqual(store.entries(on: date(8), meal: .dinner).count, 2)
        XCTAssertEqual(Set(store.entries.map(\.id)).count, 3)
        XCTAssertEqual(store.entries(on: date(7))[0], source)
    }
    @MainActor func testValidationAndBatchFailurePreserveExistingRecords() throws {
        let store = try NutritionStore(container: PersistenceFactory.makeContainer(inMemory: true), catalogue: [rice])
        let valid = FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: rice))
        var invalid = valid; invalid.id = UUID(); invalid.portion.quantity = -1
        XCTAssertFalse(store.saveEntries([valid, invalid])); XCTAssertTrue(store.entries.isEmpty)
        var reference = rice; reference.values.calories = 999
        XCTAssertFalse(store.saveFood(reference))
        XCTAssertEqual(store.foods[0].values.calories, 130)
        let unknown = NutritionFood(name: "Incomplete quick entry", values: NutritionValues(protein: 5), source: .quickAdd)
        XCTAssertNotNil(unknown.validationMessage)
    }
    @MainActor func testNutritionDeletionDoesNotTouchGymOrProfile() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try NutritionStore(container: container, catalogue: [rice])
        let gym = try GymStore(container: container); XCTAssertTrue(gym.save(RoutineTemplate.fullBody.make()))
        XCTAssertTrue(store.saveEntry(FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: rice))))
        XCTAssertTrue(store.deleteAllNutrition()); XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.foods.count, 1)
        XCTAssertEqual(try GymStore(container: container).routines.count, 1)
    }
    func testBundledCatalogueHasTraceableReferencesAndExplicitIndianEstimates() throws {
        let foods = try NutritionCatalogue.load()
        XCTAssertEqual(foods.count, 104)
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
        XCTAssertTrue(foods.allSatisfy { $0.validationMessage == nil })
        XCTAssertTrue(foods.contains { $0.matches("roti") })
        XCTAssertTrue(foods.contains { $0.matches("dahi") })
        XCTAssertTrue(foods.contains { $0.matches("paneer") })
        let estimates = foods.filter { $0.source == .estimate }
        XCTAssertEqual(estimates.count, 12)
        XCTAssertTrue(estimates.allSatisfy { $0.estimated && $0.values.sodium == nil })
        XCTAssertEqual(foods.first { $0.id == "usda-20045" }?.values.calories, 130)
    }
    @MainActor func testDiskReopenPreservesSnapshotsAndFavorites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NutritionTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("FitOut.store")
        let entry = FoodLogEntry(date: date(7), meal: .dinner, portion: FoodPortion(food: rice))
        do {
            let store = try NutritionStore(container: PersistenceFactory.makeContainer(at: url), catalogue: [rice])
            XCTAssertTrue(store.saveEntry(entry)); XCTAssertTrue(store.favorite(rice.id))
        }
        let reopened = try NutritionStore(container: PersistenceFactory.makeContainer(at: url), catalogue: [rice])
        XCTAssertEqual(reopened.entries, [entry]); XCTAssertTrue(reopened.preferences.favoriteIDs.contains(rice.id))
    }
    @MainActor func testV5StoreMigratesAdditivelyWithoutRemovingRoutines() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NutritionMigration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("FitOut.store")
        let routine = RoutineTemplate.fullBody.make()
        do {
            let schema = Schema(versionedSchema: FitOutSchemaV5.self)
            let configuration = ModelConfiguration("FitOut", schema: schema, url: url, cloudKitDatabase: .none)
            let legacy = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(legacy)
            context.insert(FitOutSchemaV3.RoutineRecord(routine)); try context.save()
        }
        let upgraded = try PersistenceFactory.makeContainer(at: url)
        XCTAssertEqual(try GymStore(container: upgraded).routines.first?.id, routine.id)
        let nutrition = try NutritionStore(container: upgraded, catalogue: [rice])
        XCTAssertTrue(nutrition.entries.isEmpty)
        XCTAssertTrue(nutrition.saveEntry(FoodLogEntry(date: date(7), meal: .lunch, portion: FoodPortion(food: rice))))
    }
    func testEditingWaterPreservesIdentityAndOldWidgetDataDecodes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NutritionWater-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSharedStore(directory: directory)
        let original = try store.logWater(250, at: date(7)).water[0]
        let updated = try store.editWater(id: original.id, milliliters: 500, date: date(8))
        XCTAssertEqual(updated.water.count, 1); XCTAssertEqual(updated.water[0].id, original.id)
        XCTAssertEqual(updated.localWater(at: date(7), calendar: calendar), 0)
        XCTAssertEqual(updated.localWater(at: date(8), calendar: calendar), 500)
        try store.removeWater(id: original.id)
        XCTAssertThrowsError(try store.editWater(id: original.id, milliliters: 250, date: date(8)))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FitOutWidgetState())) as? [String: Any])
        json.removeValue(forKey: "waterDisplayUnit")
        var snapshot = try XCTUnwrap(json["snapshot"] as? [String: Any]); snapshot.removeValue(forKey: "nutrition"); json["snapshot"] = snapshot
        let legacy = try JSONDecoder().decode(FitOutWidgetState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.waterDisplayUnit); XCTAssertNil(legacy.snapshot.nutrition)
    }
}

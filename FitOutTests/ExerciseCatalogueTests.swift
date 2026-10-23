import XCTest
import SwiftData
import UIKit
@testable import FitOut

final class ExerciseCatalogueTests: XCTestCase {
    func testLibrarySortingAndScopesCombineWithSearchAndEquipment() {
        let alpha = ExerciseDefinition(id: "a", name: "Alpha row", muscles: [.upperBack], equipment: "Cable machine")
        let custom = ExerciseDefinition(id: "c", name: "alpha row", muscles: [.upperBack], equipment: "Dumbbells", isCustom: true)
        let curl = ExerciseDefinition(id: "b", name: "Beta curl", muscles: [.biceps], equipment: "Dumbbells", isFavorite: true)
        let press = ExerciseDefinition(id: "z", name: "Z press", muscles: [.shoulders], equipment: "Barbell", isFavorite: true)
        let entries = [press, custom, curl, alpha]
        XCTAssertEqual(ExerciseSortOrder.nameAscending.sorted(entries).map(\.id), ["a", "c", "b", "z"])
        XCTAssertEqual(ExerciseSortOrder.nameDescending.sorted(entries).map(\.id), ["z", "b", "a", "c"])
        XCTAssertEqual(ExerciseSortOrder.muscle.sorted(entries).map(\.id), ["b", "z", "a", "c"])
        XCTAssertEqual(ExerciseSortOrder.equipment.sorted(entries).map(\.id), ["z", "a", "c", "b"])
        var query = ExerciseLibraryQuery(search: " ROW ", scope: .custom,
            filters: ExerciseBrowseFilters(muscles: [.upperBack], equipment: .dumbbell))
        XCTAssertEqual(query.results(in: entries).map(\.id), ["c"])
        query.scope = .favorites; query.search = "curl"; query.filters.muscles = []
        XCTAssertEqual(query.results(in: entries).map(\.id), ["b"])
        query.filters.category = .cardio
        XCTAssertTrue(query.results(in: entries).isEmpty)
    }

    func testPickerKeepsChosenOrderWhenResultsAreFilteredSortedOrRemoved() {
        let entries = [
            ExerciseDefinition(id: "a", name: "Needle press", muscles: [.chest]),
            ExerciseDefinition(id: "b", name: "B", muscles: [.upperBack]),
            ExerciseDefinition(id: "c", name: "C", muscles: [.quadriceps])
        ]
        var selection = ExercisePickerSelection()
        selection.add("c"); selection.add("a"); selection.add("b"); selection.add("a")
        let query = ExerciseLibraryQuery(search: "Needle", sort: .nameDescending)
        XCTAssertEqual(query.results(in: entries).map(\.id), ["a"])
        XCTAssertEqual(selection.exercises(in: query.sort.sorted(entries)).map(\.id), ["c", "a", "b"])
        selection.remove("a"); selection.add("a")
        XCTAssertEqual(selection.ids, ["c", "b", "a"])
        selection.retainAvailable(["a", "c"])
        XCTAssertEqual(selection.exercises(in: entries).map(\.id), ["c", "a"])
    }

    func testCatalogueHasCompleteUniqueSystemEntriesAndStableLegacyIDs() {
        let all = ExerciseCatalogue.all
        XCTAssertGreaterThanOrEqual(all.count, 140)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map { $0.name.lowercased() }).count, all.count)
        XCTAssertEqual(Array(all.prefix(13).map(\.id)), ["bench", "row", "squat", "rdl", "press", "pulldown", "curl", "extension", "raise", "calf", "pushup", "plank", "walk"])
        for exercise in all {
            XCTAssertFalse(exercise.name.isEmpty, exercise.id)
            XCTAssertFalse(exercise.muscles.isEmpty, exercise.id)
            XCTAssertFalse(exercise.instructions.isEmpty, exercise.id)
            XCTAssertFalse(exercise.equipment.isEmpty, exercise.id)
            XCTAssertFalse(exercise.isCustom, exercise.id)
            XCTAssertEqual(Set(exercise.muscles).count, exercise.muscles.count, exercise.id)
            XCTAssertTrue(Set(exercise.muscles).isDisjoint(with: exercise.secondary), exercise.id)
        }
        XCTAssertEqual(Set(all.flatMap(\.muscles)), Set(Muscle.allCases))
        XCTAssertEqual(Set(all.map(\.category)), Set(ExerciseCategory.allCases))
        for template in RoutineTemplate.allCases {
            XCTAssertTrue(template.make().days.flatMap(\.exercises).allSatisfy { ExerciseCatalogue.byID[$0.exerciseID] != nil })
        }
    }

    func testImageSlotsAreUniqueAndDoNotUseCustomOrUnknownIDs() {
        let names = ExerciseCatalogue.all.compactMap(\.imageAssetName)
        XCTAssertEqual(names.count, ExerciseCatalogue.all.count)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(ExerciseCatalogue.byID["bench"]?.imageAssetName, "exercise-bench")
        XCTAssertNil(ExerciseDefinition(id: "bench", name: "My exercise", muscles: [.chest], isCustom: true).imageAssetName)
        XCTAssertNil(ExerciseDefinition(id: "unknown", name: "Legacy exercise", muscles: [.chest]).imageAssetName)
    }

    func testSuppliedIllustrationsAreBundledForTheirExactExerciseVariants() throws {
        let illustratedIDs = [
            "machine-chest-press", "incline-machine-chest-press", "pec-deck",
            "extension", "rope-triceps-pushdown", "overhead-triceps-extension",
            "squat", "leg-press", "leg-extension", "crunch", "dragon-flag", "russian-twist",
            "pulldown", "seated-cable-row", "face-pull", "arnold-press",
            "seated-dumbbell-press", "raise", "ez-bar-curl", "incline-curl", "hammer-curl"
        ]
        for id in illustratedIDs {
            let exercise = try XCTUnwrap(ExerciseCatalogue.byID[id], id)
            let key = try XCTUnwrap(exercise.imageAssetName, id)
            let image = try XCTUnwrap(UIImage(named: key), "Missing bundled image: \(key)")
            XCTAssertGreaterThan(image.size.width, 0, id)
            XCTAssertGreaterThan(image.size.height, 0, id)
        }
        XCTAssertEqual(ExerciseCatalogue.byID["incline-machine-chest-press"]?.equipmentFilters, [.machine])
        XCTAssertTrue(try XCTUnwrap(ExerciseCatalogue.byID["rope-triceps-pushdown"]).equipmentFilters.contains(.cable))
        XCTAssertEqual(ExerciseCatalogue.byID["dragon-flag"]?.kind, .bodyweight)
        XCTAssertTrue(ExerciseFilter(search: "plate twist").matches(try XCTUnwrap(ExerciseCatalogue.byID["russian-twist"])))
    }

    func testSearchHandlesAliasesSpacingMusclesAndCombinedFilters() throws {
        let pullup = try XCTUnwrap(ExerciseCatalogue.byID["pullup"])
        XCTAssertTrue(ExerciseFilter(search: "  PULL UP  ").matches(pullup))
        XCTAssertTrue(ExerciseFilter(search: "back bar").matches(pullup))
        XCTAssertTrue(ExerciseFilter(search: "pushup").matches(try XCTUnwrap(ExerciseCatalogue.byID["pushup"])))
        let bench = try XCTUnwrap(ExerciseCatalogue.byID["bench"])
        XCTAssertTrue(ExerciseFilter(search: "BB flat", muscles: [.triceps], category: .strength, equipment: .barbell).matches(bench))
        XCTAssertFalse(ExerciseFilter(search: "bench", equipment: .dumbbell).matches(bench))
        XCTAssertFalse(ExerciseFilter(favoritesOnly: true).matches(bench))
        var favorite = bench; favorite.isFavorite = true
        XCTAssertTrue(ExerciseFilter(favoritesOnly: true).matches(favorite))
        XCTAssertTrue(ExerciseFilter(search: "abs").matches(try XCTUnwrap(ExerciseCatalogue.byID["plank"])))
        XCTAssertFalse(ExerciseFilter(search: "unlisted movement").matches(bench))
    }

    func testTrackingAndEquipmentMatchCommonExerciseTypes() throws {
        for id in ["running", "stationary-bike", "side-plank", "hamstring-stretch", "farmer-carry"] {
            XCTAssertEqual(ExerciseCatalogue.byID[id]?.kind, .duration, id)
        }
        for id in ["pullup", "pushup", "bodyweight-squat", "crunch"] {
            XCTAssertEqual(ExerciseCatalogue.byID[id]?.kind, .bodyweight, id)
        }
        for id in ["bench", "leg-press", "hammer-curl", "deadlift"] {
            XCTAssertEqual(ExerciseCatalogue.byID[id]?.kind, .weighted, id)
        }
        XCTAssertEqual(ExerciseCatalogue.byID["goblet-squat"]?.equipmentFilters, [.dumbbell, .kettlebell])
        XCTAssertTrue(ExerciseFilter(equipment: .noEquipment).matches(try XCTUnwrap(ExerciseCatalogue.byID["plank"])))
        XCTAssertFalse(ExerciseFilter(equipment: .noEquipment).matches(try XCTUnwrap(ExerciseCatalogue.byID["bench"])))
        XCTAssertTrue(ExerciseFilter(category: .mobility).matches(try XCTUnwrap(ExerciseCatalogue.byID["cat-cow"])))
    }

    @MainActor func testExistingLibraryUpgradesWithoutLosingUserDataOrDuplicatingEntries() throws {
        let container = try PersistenceFactory.makeContainer(inMemory: true)
        let context = ModelContext(container)
        var bench = try XCTUnwrap(ExerciseCatalogue.byID["bench"])
        bench.name = "Old system title"; bench.aliases = "Old aliases"; bench.isFavorite = true
        context.insert(FitOutSchemaV3.ExerciseRecord(bench))
        let custom = ExerciseDefinition(name: "My movement", muscles: [.chest], instructions: "My own cue", isCustom: true, isFavorite: true)
        context.insert(FitOutSchemaV3.ExerciseRecord(custom))
        try context.save()

        let store = try GymStore(container: container)
        XCTAssertEqual(store.exercise("bench")?.name, "Bench press")
        XCTAssertTrue(try XCTUnwrap(store.exercise("bench")).isFavorite)
        XCTAssertEqual(store.exercise(custom.id), custom)
        XCTAssertEqual(store.exercises.count, ExerciseCatalogue.all.count + 1)

        var routine = RoutineTemplate.fullBody.make()
        routine.days[0].exercises.append(PlannedExercise(exerciseID: "leg-press"))
        XCTAssertTrue(store.save(routine))
        let reopened = try GymStore(container: container)
        XCTAssertEqual(reopened.exercises.count, store.exercises.count)
        XCTAssertEqual(reopened.activeRoutine?.days[0].exercises.map(\.exerciseID), routine.days[0].exercises.map(\.exerciseID))
        XCTAssertTrue(try XCTUnwrap(reopened.exercise("bench")).isFavorite)
    }
}

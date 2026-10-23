import XCTest
@testable import FitOut
final class GymTests: XCTestCase {
    func testWeekdayMappingAndMovePreserveOtherSessions() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        XCTAssertEqual(RoutineSchedule.weekday(for: monday, calendar: calendar), 0)
        XCTAssertEqual(RoutineSchedule.weekday(for: monday.addingTimeInterval(6 * 86400), calendar: calendar), 6)
        var routine = RoutineTemplate.ppl.make(); let id = routine.days[0].id; let exercises = routine.days[0].exercises
        RoutineSchedule.move(dayID: id, to: 3, in: &routine)
        XCTAssertEqual(routine.days.first { $0.weekday == 3 }?.exercises, exercises)
        XCTAssertEqual(Set(routine.days.map(\.weekday)), Set(0..<7))
    }
    @MainActor func testRoutineCRUDAndSingleActiveSelection() throws {
        let database = try PersistenceFactory.makeContainer(inMemory: true)
        let store = try GymStore(container: database)
        XCTAssertTrue(store.routines.isEmpty)
        let initial = RoutineTemplate.fullBody.make(); XCTAssertTrue(store.save(initial))
        XCTAssertEqual(store.activeRoutine?.id, initial.id)
        var copy = store.routines[0].duplicate(); copy.isActive = true
        XCTAssertTrue(store.save(copy)); XCTAssertEqual(store.routines.filter(\.isActive).count, 1)
        XCTAssertNotEqual(copy.days[0].exercises[0].id, initial.days[0].exercises[0].id)
        copy.name = "Edited"; copy.days[0].exercises.removeFirst(); XCTAssertTrue(store.save(copy))
        let reopened = try GymStore(container: database)
        XCTAssertEqual(reopened.activeRoutine?.name, "Edited")
        XCTAssertEqual(reopened.activeRoutine?.days[0].exercises.count, 2)
        XCTAssertTrue(reopened.deleteRoutine(copy.id)); XCTAssertEqual(reopened.routines.count, 1)
    }
    @MainActor func testExerciseFavoritesCustomValidationAndDependency() throws {
        let store = try GymStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var custom = ExerciseDefinition(name: "Custom press", muscles: [.chest], isCustom: true)
        XCTAssertTrue(store.saveExercise(custom)); custom.isFavorite = true; XCTAssertTrue(store.saveExercise(custom))
        XCTAssertTrue(store.exercise(custom.id)!.isFavorite)
        var routine = RoutineTemplate.fullBody.make(); routine.days[0].exercises.append(PlannedExercise(exerciseID: custom.id))
        XCTAssertTrue(store.save(routine)); XCTAssertFalse(store.deleteCustomExercise(custom.id))
        routine.days[0].exercises[0].loadKG = .nan; XCTAssertFalse(store.save(routine))
        XCTAssertTrue(store.deleteRoutine(routine.id)); XCTAssertTrue(store.deleteCustomExercise(custom.id))
    }
}

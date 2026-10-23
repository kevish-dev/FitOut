import Foundation
import SwiftData
import Observation

struct ValidationError: LocalizedError { let message: String; var errorDescription: String? { message } }

@MainActor @Observable final class GymStore {
    private let context: ModelContext
    private(set) var routines: [Routine] = []
    private(set) var exercises: [ExerciseDefinition] = []
    var error: String?
    init(container: ModelContainer) throws {
        context = ModelContext(container); context.autosaveEnabled = false
        let existing = Set(try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).map(\.id))
        for exercise in ExerciseCatalogue.all where !existing.contains(exercise.id) { context.insert(FitOutSchemaV3.ExerciseRecord(exercise)) }
        try context.save(); try reload()
    }
    var activeRoutine: Routine? { routines.first(where: \.isActive) }
    func exercise(_ id: String) -> ExerciseDefinition? { exercises.first { $0.id == id } }
    func homeInput(at date: Date = .now, calendar: Calendar = .current) -> HomeWorkoutInput {
        guard let routine = activeRoutine else { return HomeWorkoutInput() }
        let day = RoutineSchedule.day(in: routine, at: date, calendar: calendar)
        return HomeWorkoutInput(hasRoutine: true, isRestDay: day?.kind == .rest, plannedTitle: day?.kind == .workout ? day?.title : nil, exerciseCount: day?.exercises.count ?? 0, minutes: day?.durationMinutes)
    }
    private func reload() throws {
        routines = try context.fetch(FetchDescriptor<FitOutSchemaV3.RoutineRecord>()).map(\.value).sorted { $0.createdAt < $1.createdAt }
        exercises = try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).map(\.value).sorted { $0.name < $1.name }
    }
    @discardableResult func save(_ input: Routine) -> Bool {
        transact {
            if let message = input.validationMessage { throw ValidationError(message: message) }
            let known = Set(exercises.map(\.id))
            guard input.days.flatMap(\.exercises).allSatisfy({ known.contains($0.exerciseID) }) else { throw ValidationError(message: "An exercise is no longer available. Replace it before saving.") }
            var value = input; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines); value.updatedAt = .now
            let records = try context.fetch(FetchDescriptor<FitOutSchemaV3.RoutineRecord>())
            if records.isEmpty { value.isActive = true }
            if value.isActive { for record in records { record.isActive = false } }
            if let record = records.first(where: { $0.id == value.id }) {
                for old in record.days { context.delete(old) }
                record.name = value.name; record.isActive = value.isActive; record.updatedAt = value.updatedAt
                record.days = value.days.map(FitOutSchemaV3.DayRecord.init)
            } else { context.insert(FitOutSchemaV3.RoutineRecord(value)) }
        }
    }
    @discardableResult func deleteRoutine(_ id: UUID) -> Bool { transact { if let record = try context.fetch(FetchDescriptor<FitOutSchemaV3.RoutineRecord>()).first(where: { $0.id == id }) { context.delete(record) } } }
    @discardableResult func saveExercise(_ value: ExerciseDefinition) -> Bool {
        transact {
            guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !value.muscles.isEmpty else { throw ValidationError(message: "Enter an exercise name and at least one primary muscle.") }
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).first(where: { $0.id == value.id }) {
                record.name = value.name; record.aliases = value.aliases; record.muscles = value.muscles.map(\.rawValue); record.secondary = value.secondary.map(\.rawValue)
                record.equipment = value.equipment; record.pattern = value.pattern; record.instructions = value.instructions; record.kind = value.kind.rawValue; record.isFavorite = value.isFavorite
            } else { context.insert(FitOutSchemaV3.ExerciseRecord(value)) }
        }
    }
    @discardableResult func deleteCustomExercise(_ id: String) -> Bool {
        transact {
            guard !routines.flatMap(\.days).flatMap(\.exercises).contains(where: { $0.exerciseID == id }) else { throw ValidationError(message: "Remove this exercise from routines before deleting it.") }
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).first(where: { $0.id == id && $0.isCustom }) { context.delete(record) }
        }
    }
    private func transact(_ action: () throws -> Void) -> Bool {
        do { try action(); try context.save(); try reload(); error = nil; return true }
        catch { context.rollback(); self.error = error.localizedDescription; return false }
    }
}

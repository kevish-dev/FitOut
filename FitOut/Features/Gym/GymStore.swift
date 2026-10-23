import Foundation
import SwiftData
import Observation

@MainActor @Observable final class GymStore {
    private let context: ModelContext
    private(set) var routines: [Routine] = []
    private(set) var exercises: [ExerciseDefinition] = []
    private(set) var drafts: [RoutineDraft] = []
    private(set) var savedWorkouts: [SavedWorkout] = []
    var error: String?
    var onChange: (() -> Void)?
    init(container: ModelContainer) throws {
        context = ModelContext(container); context.autosaveEnabled = false
        let existing = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).map { ($0.id, $0) })
        for exercise in ExerciseCatalogue.all {
            if let record = existing[exercise.id] {
                // System metadata can evolve; user favorites and custom records remain local.
                guard !record.isCustom else { continue }
                record.name = exercise.name; record.aliases = exercise.aliases
                record.muscles = exercise.muscles.map(\.rawValue); record.secondary = exercise.secondary.map(\.rawValue)
                record.equipment = exercise.equipment; record.pattern = exercise.pattern
                record.instructions = exercise.instructions; record.kind = exercise.kind.rawValue
            } else { context.insert(FitOutSchemaV3.ExerciseRecord(exercise)) }
        }
        try context.save(); try reload()
    }
    var activeRoutine: Routine? { routines.first { $0.isActive && $0.archivedAt == nil } }
    var resumableDraft: RoutineDraft? {
        drafts.first { draft in routines.first(where: { $0.id == draft.id })?.archivedAt == nil }
    }
    func exercise(_ id: String) -> ExerciseDefinition? { exercises.first { $0.id == id } }
    func homeInput(at date: Date = .now, calendar: Calendar = .current) -> HomeWorkoutInput {
        guard let routine = activeRoutine, routine.days.contains(where: { $0.kind == .workout }) else { return HomeWorkoutInput() }
        let day = routine.hasStarted(at: date, calendar: calendar) ? RoutineSchedule.day(in: routine, at: date, calendar: calendar) : nil
        return HomeWorkoutInput(hasRoutine: true, isRestDay: day?.kind == .rest, plannedTitle: day?.kind == .workout ? day?.title : nil, exerciseCount: day?.exercises.count ?? 0, minutes: day?.durationMinutes)
    }
    func reload() throws {
        let details = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<FitOutSchemaV5.RoutineDetails>()).map { ($0.id, $0.payload) })
        routines = try context.fetch(FetchDescriptor<FitOutSchemaV3.RoutineRecord>()).map { record in
            guard let data = details[record.id] else { return record.value }
            var value = try JSONDecoder().decode(Routine.self, from: data)
            value.isActive = record.isActive
            return value
        }.sorted { $0.createdAt < $1.createdAt }
        exercises = try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).map(\.value).sorted { $0.name < $1.name }
        drafts = try context.fetch(FetchDescriptor<FitOutSchemaV5.DraftRecord>()).map { try JSONDecoder().decode(RoutineDraft.self, from: $0.payload) }.sorted { $0.updatedAt > $1.updatedAt }
        savedWorkouts = try context.fetch(FetchDescriptor<FitOutSchemaV5.SavedWorkoutRecord>()).map { try JSONDecoder().decode(SavedWorkout.self, from: $0.payload) }.sorted { $0.day.title < $1.day.title }
    }
    @discardableResult func save(_ input: Routine, discardDraft: Bool = false) -> Bool {
        transact {
            if let message = input.validationMessage { throw ValidationError(message: message) }
            let known = Set(exercises.map(\.id))
            guard input.days.flatMap(\.exercises).allSatisfy({ known.contains($0.exerciseID) }) else { throw ValidationError(message: "An exercise is no longer available. Replace it before saving.") }
            if let message = readinessError(for: input, requireComplete: false) { throw ValidationError(message: message) }
            var value = input; value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines); value.updatedAt = .now
            let records = try context.fetch(FetchDescriptor<FitOutSchemaV3.RoutineRecord>())
            if records.isEmpty && value.archivedAt == nil { value.isActive = true }
            if value.archivedAt != nil { value.isActive = false }
            if value.isActive { for record in records { record.isActive = false } }
            if let record = records.first(where: { $0.id == value.id }) {
                for old in record.days { context.delete(old) }
                record.name = value.name; record.isActive = value.isActive; record.updatedAt = value.updatedAt
                record.days = value.days.map(FitOutSchemaV3.DayRecord.init)
            } else { context.insert(FitOutSchemaV3.RoutineRecord(value)) }
            let payload = try JSONEncoder().encode(value)
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV5.RoutineDetails>()).first(where: { $0.id == value.id }) { record.payload = payload }
            else { context.insert(FitOutSchemaV5.RoutineDetails(id: value.id, payload: payload)) }
            if discardDraft, let draft = try context.fetch(FetchDescriptor<FitOutSchemaV5.DraftRecord>()).first(where: { $0.id == value.id }) { context.delete(draft) }
        }
    }
    func readinessError(for routine: Routine, requireComplete: Bool = true) -> String? {
        if let message = requireComplete ? routine.readinessMessage : routine.validationMessage { return message }
        for plan in routine.trainingDays.flatMap(\.exercises) {
            guard let exercise = exercise(plan.exerciseID) else { return "Replace the unavailable exercise before saving." }
            if exercise.kind == .duration && !plan.resolvedSets.allSatisfy({ $0.seconds > 0 }) { return "Set a duration for each \(exercise.name) set." }
        }
        return nil
    }
    @discardableResult func saveDraft(_ input: RoutineDraft) -> Bool {
        transact {
            var draft = input; draft.updatedAt = .now
            let payload = try JSONEncoder().encode(draft)
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV5.DraftRecord>()).first(where: { $0.id == draft.id }) { record.payload = payload }
            else { context.insert(FitOutSchemaV5.DraftRecord(id: draft.id, payload: payload)) }
        }
    }
    @discardableResult func discardDraft(_ id: UUID) -> Bool {
        transact { if let record = try context.fetch(FetchDescriptor<FitOutSchemaV5.DraftRecord>()).first(where: { $0.id == id }) { context.delete(record) } }
    }
    @discardableResult func saveWorkout(_ day: RoutineDay) -> Bool {
        transact {
            guard day.kind == .workout, !day.exercises.isEmpty, !day.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError(message: "Name the workout and add exercises before saving it for reuse.")
            }
            guard (0..<7).contains(day.weekday) else { throw ValidationError(message: "Choose a valid weekday.") }
            var proposal = Routine(name: day.title)
            proposal.days[day.weekday] = day
            if let message = readinessError(for: proposal) { throw ValidationError(message: message) }
            let value = SavedWorkout(day: day.independentCopy())
            context.insert(FitOutSchemaV5.SavedWorkoutRecord(id: value.id, payload: try JSONEncoder().encode(value)))
        }
    }
    @discardableResult func deleteSavedWorkout(_ id: UUID) -> Bool {
        transact { if let record = try context.fetch(FetchDescriptor<FitOutSchemaV5.SavedWorkoutRecord>()).first(where: { $0.id == id }) { context.delete(record) } }
    }
    @discardableResult func deleteRoutine(_ id: UUID) -> Bool {
        transact {
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV3.RoutineRecord>()).first(where: { $0.id == id }) { context.delete(record) }
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV5.RoutineDetails>()).first(where: { $0.id == id }) { context.delete(record) }
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV5.DraftRecord>()).first(where: { $0.id == id }) { context.delete(record) }
        }
    }
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
            let referencedDays = routines.flatMap(\.days) + drafts.flatMap { $0.routine.days } + savedWorkouts.map(\.day)
            guard !referencedDays.flatMap(\.exercises).contains(where: { $0.exerciseID == id }) else { throw ValidationError(message: "Remove this exercise from routines, drafts and saved workouts before deleting it.") }
            if let record = try context.fetch(FetchDescriptor<FitOutSchemaV3.ExerciseRecord>()).first(where: { $0.id == id && $0.isCustom }) { context.delete(record) }
        }
    }
    private func transact(_ action: () throws -> Void) -> Bool {
        do { try action(); try context.save(); try reload(); error = nil; onChange?(); return true }
        catch { context.rollback(); self.error = error.localizedDescription; return false }
    }
}

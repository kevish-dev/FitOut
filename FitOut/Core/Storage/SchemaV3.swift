import Foundation
import SwiftData

enum FitOutSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { FitOutSchemaV2.models + [ExerciseRecord.self, RoutineRecord.self, DayRecord.self, PlanRecord.self] }
    @Model final class ExerciseRecord {
        @Attribute(.unique) var id: String
        var name: String; var aliases: String; var muscles: [String]; var secondary: [String]
        var equipment: String; var pattern: String; var instructions: String; var kind: String
        var isCustom: Bool; var isFavorite: Bool
        init(_ v: ExerciseDefinition) { id = v.id; name = v.name; aliases = v.aliases; muscles = v.muscles.map(\.rawValue); secondary = v.secondary.map(\.rawValue); equipment = v.equipment; pattern = v.pattern; instructions = v.instructions; kind = v.kind.rawValue; isCustom = v.isCustom; isFavorite = v.isFavorite }
        var value: ExerciseDefinition { .init(id: id, name: name, aliases: aliases, muscles: muscles.compactMap(Muscle.init(rawValue:)), secondary: secondary.compactMap(Muscle.init(rawValue:)), equipment: equipment, pattern: pattern, instructions: instructions, kind: ExerciseKind(rawValue: kind) ?? .weighted, isCustom: isCustom, isFavorite: isFavorite) }
    }
    @Model final class RoutineRecord {
        @Attribute(.unique) var id: UUID
        var name: String; var isActive: Bool; var createdAt: Date; var updatedAt: Date
        @Relationship(deleteRule: .cascade) var days: [DayRecord]
        init(_ v: Routine) { id = v.id; name = v.name; isActive = v.isActive; createdAt = v.createdAt; updatedAt = v.updatedAt; days = v.days.map(DayRecord.init) }
        var value: Routine { .init(id: id, name: name, isActive: isActive, days: days.map(\.value).sorted { $0.weekday < $1.weekday }, createdAt: createdAt, updatedAt: updatedAt) }
    }
    @Model final class DayRecord {
        var id: UUID; var weekday: Int; var title: String; var kind: String; var muscles: [String]; var durationMinutes: Int?
        @Relationship(deleteRule: .cascade) var exercises: [PlanRecord]
        init(_ v: RoutineDay) { id = v.id; weekday = v.weekday; title = v.title; kind = v.kind.rawValue; muscles = v.muscles.map(\.rawValue); durationMinutes = v.durationMinutes; exercises = v.exercises.enumerated().map { PlanRecord($0.element, position: $0.offset) } }
        var value: RoutineDay { .init(id: id, weekday: weekday, title: title, kind: RoutineDayKind(rawValue: kind) ?? .flexible, muscles: muscles.compactMap(Muscle.init(rawValue:)), durationMinutes: durationMinutes, exercises: exercises.sorted { $0.position < $1.position }.map(\.value)) }
    }
    @Model final class PlanRecord {
        var id: UUID; var exerciseID: String; var position: Int; var sets: Int; var repMin: Int; var repMax: Int; var restSeconds: Int; var loadKG: Double?; var notes: String; var warmupSets: Int
        init(_ v: PlannedExercise, position: Int) { id = v.id; exerciseID = v.exerciseID; self.position = position; sets = v.sets; repMin = v.repMin; repMax = v.repMax; restSeconds = v.restSeconds; loadKG = v.loadKG; notes = v.notes; warmupSets = v.warmupSets }
        var value: PlannedExercise { .init(id: id, exerciseID: exerciseID, sets: sets, repMin: repMin, repMax: repMax, restSeconds: restSeconds, loadKG: loadKG, notes: notes, warmupSets: warmupSets) }
    }
}

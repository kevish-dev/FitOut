import Foundation
import SwiftData

enum FitOutSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] { FitOutSchemaV3.models + [SessionRecord.self, EntryRecord.self, SetRecord.self] }
    @Model final class SessionRecord {
        @Attribute(.unique) var id: UUID
        var routineID: UUID?; var title: String; var startedAt: Date; var endedAt: Date?; var status: String; var pausedAt: Date?; var pausedSeconds: Double; var restUntil: Date?; var notes: String
        @Relationship(deleteRule: .cascade) var entries: [EntryRecord]
        init(_ v: WorkoutSession) { id = v.id; routineID = v.routineID; title = v.title; startedAt = v.startedAt; endedAt = v.endedAt; status = v.status.rawValue; pausedAt = v.pausedAt; pausedSeconds = v.pausedSeconds; restUntil = v.restUntil; notes = v.notes; entries = v.entries.enumerated().map { EntryRecord($0.element, position: $0.offset) } }
        var value: WorkoutSession { .init(id: id, routineID: routineID, title: title, startedAt: startedAt, endedAt: endedAt, status: SessionStatus(rawValue: status) ?? .abandoned, pausedAt: pausedAt, pausedSeconds: pausedSeconds, restUntil: restUntil, notes: notes, entries: entries.sorted { $0.position < $1.position }.map(\.value)) }
    }
    @Model final class EntryRecord {
        var id: UUID; var position: Int; var exerciseID: String; var name: String; var muscles: [String]; var kind: String; var restSeconds: Int; var notes: String; var skipped: Bool
        @Relationship(deleteRule: .cascade) var sets: [SetRecord]
        init(_ v: WorkoutEntry, position: Int) { id = v.id; self.position = position; exerciseID = v.exercise.id; name = v.exercise.name; muscles = v.exercise.muscles.map(\.rawValue); kind = v.exercise.kind.rawValue; restSeconds = v.restSeconds; notes = v.notes; skipped = v.skipped; sets = v.sets.enumerated().map { SetRecord($0.element, position: $0.offset) } }
        var value: WorkoutEntry { .init(id: id, exercise: ExerciseDefinition(id: exerciseID, name: name, muscles: muscles.compactMap(Muscle.init(rawValue:)), kind: ExerciseKind(rawValue: kind) ?? .weighted), sets: sets.sorted { $0.position < $1.position }.map(\.value), restSeconds: restSeconds, notes: notes, skipped: skipped) }
    }
    @Model final class SetRecord {
        var id: UUID; var position: Int; var type: String; var reps: Int; var loadKG: Double; var seconds: Double; var distanceMeters: Double; var rpe: Double?; var completedAt: Date?
        init(_ v: WorkoutSet, position: Int) { id = v.id; self.position = position; type = v.type.rawValue; reps = v.reps; loadKG = v.loadKG; seconds = v.seconds; distanceMeters = v.distanceMeters; rpe = v.rpe; completedAt = v.completedAt }
        var value: WorkoutSet { .init(id: id, type: SetType(rawValue: type) ?? .working, reps: reps, loadKG: loadKG, seconds: seconds, distanceMeters: distanceMeters, rpe: rpe, completedAt: completedAt) }
    }
}

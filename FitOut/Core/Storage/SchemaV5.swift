import Foundation
import SwiftData

// Additive payload records preserve the original V1–V4 model definitions.
// Existing stores gain these tables without rewriting routine or session history.
enum FitOutSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        FitOutSchemaV4.models + [RoutineDetails.self, DraftRecord.self, SavedWorkoutRecord.self, SessionDetails.self]
    }
    @Model final class RoutineDetails {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class DraftRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class SavedWorkoutRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
    @Model final class SessionDetails {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
}

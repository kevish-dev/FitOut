import Foundation

enum SessionStatus: String, Codable, CaseIterable { case inProgress, paused, completed, skipped, abandoned }
enum SetType: String, Codable, CaseIterable { case warmup = "Warm-up", working = "Working", drop = "Drop set" }
struct WorkoutSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: SetType = .working
    var reps = 8
    var loadKG = 0.0
    var seconds = 0.0
    var distanceMeters = 0.0
    var rpe: Double?
    var completedAt: Date?
    var restSeconds: Int?
    var targetRPE: Double?
    var targetRepMax: Int?
    var plannedTarget: PlannedSet?
    var isValid: Bool {
        (0...1000).contains(reps) && loadKG.isFinite && (0...1000).contains(loadKG)
            && seconds.isFinite && (0...86400).contains(seconds)
            && distanceMeters.isFinite && (0...1_000_000).contains(distanceMeters)
            && (rpe == nil || (rpe!.isFinite && (1...10).contains(rpe!)))
            && (restSeconds == nil || (0...3600).contains(restSeconds!))
            && (targetRPE == nil || (targetRPE!.isFinite && (1...10).contains(targetRPE!)))
            && (targetRepMax == nil || (1...100).contains(targetRepMax!))
            && (plannedTarget == nil || plannedTarget!.isValid)
    }
}
struct WorkoutEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var exercise: ExerciseDefinition
    var sets: [WorkoutSet] = []
    var restSeconds = 90
    var notes = ""
    var skipped = false
}
struct WorkoutSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var routineID: UUID?
    var title: String
    var startedAt = Date()
    var endedAt: Date?
    var status: SessionStatus = .inProgress
    var pausedAt: Date?
    var pausedSeconds = 0.0
    var restUntil: Date?
    var notes = ""
    var entries: [WorkoutEntry] = []
    var isActive: Bool { status == .inProgress || status == .paused }
    var completedSets: [WorkoutSet] { entries.flatMap(\.sets).filter { $0.completedAt != nil } }
    var completedExercises: Int { entries.filter { $0.sets.contains { $0.completedAt != nil } }.count }
    func duration(at now: Date = .now) -> Double { max(0, (endedAt ?? pausedAt ?? now).timeIntervalSince(startedAt) - pausedSeconds) }
    var volumeKG: Double {
        entries.filter { $0.exercise.kind == .weighted }.flatMap(\.sets)
            .filter { $0.completedAt != nil && $0.type != .warmup && $0.isValid }
            .reduce(0) { $0 + $1.loadKG * Double($1.reps) }
    }
}

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
    var startedAt: Date?
    var startedActiveSeconds: TimeInterval?
    var loggedActiveSeconds: TimeInterval?
    var timedActiveSeconds: TimeInterval?
    var editedInputs: Set<WorkoutInputField>?
    var isValid: Bool {
        (0...1000).contains(reps) && loadKG.isFinite && (0...1000).contains(loadKG)
            && seconds.isFinite && (0...86400).contains(seconds)
            && distanceMeters.isFinite && (0...1_000_000).contains(distanceMeters)
            && (rpe == nil || (rpe!.isFinite && (1...10).contains(rpe!)))
            && (restSeconds == nil || (0...3600).contains(restSeconds!))
            && (targetRPE == nil || (targetRPE!.isFinite && (1...10).contains(targetRPE!)))
            && (targetRepMax == nil || (1...100).contains(targetRepMax!))
            && (plannedTarget == nil || plannedTarget!.isValid)
            && [startedActiveSeconds, loggedActiveSeconds, timedActiveSeconds].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 }
    }
    func nextWorkingSet() -> WorkoutSet {
        WorkoutSet(reps: reps, loadKG: loadKG, seconds: seconds, distanceMeters: distanceMeters)
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
    var telemetry: WorkoutTelemetry?
    var inputMemoryVersion: Int?
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

extension WorkoutSession {
    var remainingSetCount: Int {
        entries.filter { !$0.skipped }.flatMap(\.sets).filter { $0.completedAt == nil }.count
    }
    // Skipped, unlogged sets are not a goal; previously logged sets stay counted.
    var trackedSetCount: Int { completedSets.count + remainingSetCount }
    var setProgress: Double { trackedSetCount == 0 ? 0 : Double(completedSets.count) / Double(trackedSetCount) }
    func restRemaining(at now: Date) -> TimeInterval {
        guard let restUntil else { return 0 }
        return max(0, restUntil.timeIntervalSince(status == .paused ? pausedAt ?? now : now))
    }
    var currentRestDuration: TimeInterval {
        let logged = entries.flatMap { entry in entry.sets.compactMap { set -> (Date, Int)? in
            guard let date = set.completedAt else { return nil }
            return (date, set.restSeconds ?? entry.restSeconds)
        } }
        return Double(logged.max { $0.0 < $1.0 }?.1 ?? 0)
    }
}

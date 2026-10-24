import Foundation

struct ValidationError: LocalizedError { let message: String; var errorDescription: String? { message } }

struct PlannedSet: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: SetType = .working
    var repMin = 8
    var repMax = 12
    var loadKG: Double?
    var seconds = 0.0
    var distanceMeters = 0.0
    var restSeconds: Int? // nil inherits the exercise default
    var targetRPE: Double?

    var isValid: Bool {
        (1...100).contains(repMin) && (repMin...100).contains(repMax)
            && (loadKG == nil || (loadKG!.isFinite && (0...1000).contains(loadKG!)))
            && seconds.isFinite && (0...86400).contains(seconds)
            && distanceMeters.isFinite && (0...1_000_000).contains(distanceMeters)
            && (restSeconds == nil || (0...3600).contains(restSeconds!))
            && (targetRPE == nil || (targetRPE!.isFinite && (1...10).contains(targetRPE!)))
    }

    func duplicate() -> PlannedSet { var value = self; value.id = UUID(); return value }
}

extension PlannedExercise {
    var resolvedSets: [PlannedSet] {
        if let setTargets { return setTargets }
        return (0..<(max(0, warmupSets) + max(0, sets))).map { index in
            PlannedSet(type: index < warmupSets ? .warmup : .working, repMin: repMin,
                       repMax: repMax, loadKG: loadKG)
        }
    }
    var setCount: Int { setTargets?.count ?? sets + warmupSets }
    func independentCopy() -> PlannedExercise {
        var value = self
        value.id = UUID()
        value.setTargets = setTargets?.map { $0.duplicate() }
        return value
    }
    static func make(for exercise: ExerciseDefinition) -> PlannedExercise {
        var plan = PlannedExercise(exerciseID: exercise.id)
        if exercise.kind == .duration { plan.setTargets = [PlannedSet(seconds: 30)] }
        return plan
    }
}

extension RoutineDay {
    func independentCopy() -> RoutineDay {
        var value = self; value.id = UUID()
        value.exercises = exercises.map { $0.independentCopy() }
        return value
    }
}

extension Routine {
    var trainingDays: [RoutineDay] { days.filter { $0.kind == .workout }.sorted { $0.weekday < $1.weekday } }
    var readinessMessage: String? {
        if let validationMessage { return validationMessage }
        if trainingDays.isEmpty { return "Choose at least one training day." }
        if let day = trainingDays.first(where: { $0.exercises.isEmpty }) {
            return "Add an exercise to \(RoutineSchedule.weekdays[day.weekday])."
        }
        return nil
    }
    func hasStarted(at date: Date, calendar: Calendar = .current) -> Bool {
        guard let startsOn else { return true }
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: startsOn)
    }
}

extension RoutineSchedule {
    static func copy(_ source: RoutineDay, to weekday: Int, in routine: inout Routine) {
        guard let index = routine.days.firstIndex(where: { $0.weekday == weekday }) else { return }
        let destinationID = routine.days[index].id
        var copy = source.independentCopy()
        copy.id = destinationID; copy.weekday = weekday
        routine.days[index] = copy
    }
}

enum RoutineEditorStage: String, Codable, CaseIterable, Identifiable {
    case schedule = "Schedule", workouts = "Workouts", review = "Review"
    var id: String { rawValue }
}
struct RoutineDraft: Identifiable, Codable, Equatable {
    var routine: Routine
    var stage: RoutineEditorStage = .schedule
    var weekday = 0
    var updatedAt = Date()
    var id: UUID { routine.id }
}
struct SavedWorkout: Identifiable, Codable, Equatable {
    var id = UUID()
    var day: RoutineDay
}

/// Supplemental fields leave the existing V1–V4 records and history unchanged.
struct SessionPlanDetails: Codable {
    struct SetDetail: Codable {
        var restSeconds: Int?
        var targetRPE: Double?
        var targetRepMax: Int?
        var plannedTarget: PlannedSet?
        var startedAt: Date?
        var startedActiveSeconds: TimeInterval?
        var loggedActiveSeconds: TimeInterval?
        var timedActiveSeconds: TimeInterval?
        var editedInputs: Set<WorkoutInputField>?
    }
    var sets: [UUID: SetDetail]
    var telemetry: WorkoutTelemetry?
    var inputMemoryVersion: Int?
    init(_ session: WorkoutSession) {
        sets = Dictionary(uniqueKeysWithValues: session.entries.flatMap(\.sets).map {
            ($0.id, SetDetail(restSeconds: $0.restSeconds, targetRPE: $0.targetRPE, targetRepMax: $0.targetRepMax, plannedTarget: $0.plannedTarget,
                startedAt: $0.startedAt, startedActiveSeconds: $0.startedActiveSeconds, loggedActiveSeconds: $0.loggedActiveSeconds, timedActiveSeconds: $0.timedActiveSeconds, editedInputs: $0.editedInputs))
        })
        telemetry = session.telemetry
        inputMemoryVersion = session.inputMemoryVersion
    }
    func applying(to session: WorkoutSession) -> WorkoutSession {
        var result = session
        result.telemetry = telemetry
        result.inputMemoryVersion = inputMemoryVersion
        for entry in result.entries.indices {
            for index in result.entries[entry].sets.indices {
                let id = result.entries[entry].sets[index].id
                guard let detail = sets[id] else { continue }
                result.entries[entry].sets[index].restSeconds = detail.restSeconds
                result.entries[entry].sets[index].targetRPE = detail.targetRPE
                result.entries[entry].sets[index].targetRepMax = detail.targetRepMax
                result.entries[entry].sets[index].plannedTarget = detail.plannedTarget
                result.entries[entry].sets[index].startedAt = detail.startedAt
                result.entries[entry].sets[index].startedActiveSeconds = detail.startedActiveSeconds
                result.entries[entry].sets[index].loggedActiveSeconds = detail.loggedActiveSeconds
                result.entries[entry].sets[index].timedActiveSeconds = detail.timedActiveSeconds
                result.entries[entry].sets[index].editedInputs = detail.editedInputs
            }
        }
        return result
    }
}

enum PlannedWorkoutFactory {
    static func make(day: RoutineDay, routineID: UUID?, catalogue: [ExerciseDefinition], now: Date) throws -> WorkoutSession {
        guard day.kind == .workout, !day.exercises.isEmpty else { throw ValidationError(message: "Add exercises to this workout before starting.") }
        var result = WorkoutSession(routineID: routineID, title: day.title, startedAt: now, notes: day.notes ?? "")
        result.entries = try day.exercises.map { plan in
            guard let exercise = catalogue.first(where: { $0.id == plan.exerciseID }) else {
                throw ValidationError(message: "An exercise is unavailable. Edit your routine before starting.")
            }
            guard (1...30).contains(plan.sets), (0...10).contains(plan.warmupSets), (0...3600).contains(plan.restSeconds) else {
                throw ValidationError(message: "Check the set count and rest for \(exercise.name).")
            }
            let targets = plan.resolvedSets
            guard !targets.isEmpty, targets.count <= 40, targets.allSatisfy(\.isValid),
                  exercise.kind != .duration || targets.allSatisfy({ $0.seconds > 0 }) else {
                throw ValidationError(message: "Check the set targets for \(exercise.name). Timed sets need a duration.")
            }
            let sets = targets.map {
                WorkoutSet(type: $0.type, reps: $0.repMin, loadKG: $0.loadKG ?? 0, seconds: $0.seconds,
                           distanceMeters: $0.distanceMeters, restSeconds: $0.restSeconds,
                           targetRPE: $0.targetRPE, targetRepMax: $0.repMax, plannedTarget: $0)
            }
            return WorkoutEntry(exercise: exercise, sets: sets, restSeconds: plan.restSeconds, notes: plan.notes)
        }
        return result
    }
}

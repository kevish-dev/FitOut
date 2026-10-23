import Foundation

enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest, shoulders, biceps, triceps, forearms, abdominals, obliques, quadriceps, calves, upperBack, lowerBack, glutes, hamstrings
    var id: String { rawValue }
    var title: String { switch self { case .upperBack: "Upper back"; case .lowerBack: "Lower back"; default: rawValue.capitalized } }
}
enum ExerciseKind: String, Codable, CaseIterable { case weighted, bodyweight, duration }
struct ExerciseDefinition: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var aliases = ""
    var muscles: [Muscle]
    var secondary: [Muscle] = []
    var equipment = "None"
    var pattern = "Other"
    var instructions = ""
    var kind: ExerciseKind = .weighted
    var isCustom = false
    var isFavorite = false
}
struct PlannedExercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var exerciseID: String
    var sets = 3
    var repMin = 8
    var repMax = 12
    var restSeconds = 90
    var loadKG: Double?
    var notes = ""
    var warmupSets = 0
    var setTargets: [PlannedSet]?
}
enum RoutineDayKind: String, Codable, CaseIterable { case workout = "Workout", rest = "Rest day", flexible = "Flexible day" }
struct RoutineDay: Identifiable, Codable, Equatable {
    var id = UUID()
    var weekday: Int
    var title = ""
    var kind: RoutineDayKind = .flexible
    var muscles: [Muscle] = []
    var durationMinutes: Int?
    var exercises: [PlannedExercise] = []
    var notes: String?
}
struct Routine: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var isActive = false
    var days: [RoutineDay] = (0..<7).map { RoutineDay(weekday: $0) }
    var createdAt = Date()
    var updatedAt = Date()
    var archivedAt: Date?
    var startsOn: Date?
    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the routine a name." }
        if days.count != 7 || Set(days.map(\.weekday)) != Set(0..<7) { return "A routine needs one entry for each weekday." }
        for day in days where day.kind == .workout {
            if day.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give each workout day a title." }
            if let minutes = day.durationMinutes, !(1...600).contains(minutes) { return "Duration must be 1–600 minutes." }
            for exercise in day.exercises {
                if !(1...30).contains(exercise.sets) || !(0...10).contains(exercise.warmupSets) || !(1...100).contains(exercise.repMin) || !(exercise.repMin...100).contains(exercise.repMax) || !(0...3600).contains(exercise.restSeconds) { return "Check the set, rep and rest values." }
                if let load = exercise.loadKG, !load.isFinite || !(0...1000).contains(load) { return "Load must be between 0 and 1000 kg." }
                if let targets = exercise.setTargets,
                   targets.isEmpty || targets.count > 40 || !targets.allSatisfy(\.isValid) {
                    return "Each exercise needs 1–40 valid sets. Check reps, load, rest and effort targets."
                }
            }
        }
        return nil
    }
    func duplicate() -> Routine {
        var copy = self; copy.id = UUID(); copy.name += " copy"; copy.isActive = false; copy.createdAt = .now; copy.updatedAt = .now
        copy.archivedAt = nil
        copy.days = days.map { $0.independentCopy() }
        return copy
    }
}
enum RoutineSchedule {
    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    static func weekday(for date: Date, calendar: Calendar = .current) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }
    static func day(in routine: Routine, at date: Date, calendar: Calendar = .current) -> RoutineDay? { routine.days.first { $0.weekday == weekday(for: date, calendar: calendar) } }
    static func move(dayID: UUID, to weekday: Int, in routine: inout Routine) {
        guard let from = routine.days.firstIndex(where: { $0.id == dayID }), let to = routine.days.firstIndex(where: { $0.weekday == weekday }) else { return }
        let old = routine.days[from].weekday; routine.days[from].weekday = weekday; routine.days[to].weekday = old
    }
}

enum RoutineTemplate: String, CaseIterable, Identifiable {
    case custom = "Custom", ppl = "Push / Pull / Legs", upperLower = "Upper / Lower", fullBody = "Full Body", arnold = "Arnold Split", bro = "Bro Split"
    var id: String { rawValue }
    func make() -> Routine {
        var routine = Routine(name: rawValue)
        let titles: [String]
        switch self {
        case .custom: return routine
        case .ppl: titles = ["Push", "Pull", "Legs", "Rest", "Push", "Pull", "Legs"]
        case .upperLower: titles = ["Upper", "Lower", "Rest", "Upper", "Lower", "Rest", "Rest"]
        case .fullBody: titles = ["Full body", "Rest", "Full body", "Rest", "Full body", "Rest", "Rest"]
        case .arnold: titles = ["Chest & back", "Shoulders & arms", "Legs", "Rest", "Chest & back", "Shoulders & arms", "Legs"]
        case .bro: titles = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Rest", "Rest"]
        }
        for index in 0..<7 {
            let title = titles[index]; routine.days[index].title = title
            routine.days[index].kind = title == "Rest" ? .rest : .workout
            let ids: [String]
            switch title {
            case "Push", "Chest": ids = ["bench", "press", "pushup"]
            case "Pull", "Back": ids = ["row", "pulldown", "curl"]
            case "Legs", "Lower": ids = ["squat", "rdl", "calf"]
            case "Upper": ids = ["bench", "row", "press"]
            case "Full body": ids = ["squat", "bench", "row"]
            case "Shoulders": ids = ["press", "raise"]
            case "Arms": ids = ["curl", "extension"]
            case "Chest & back": ids = ["bench", "row", "pulldown"]
            case "Shoulders & arms": ids = ["press", "raise", "curl", "extension"]
            default: ids = []
            }
            routine.days[index].exercises = ids.map { PlannedExercise(exerciseID: $0) }
            routine.days[index].muscles = Array(Set(ExerciseCatalogue.all.filter { ids.contains($0.id) }.flatMap(\.muscles))).sorted { $0.rawValue < $1.rawValue }
        }
        return routine
    }
}

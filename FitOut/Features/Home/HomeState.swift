import Foundation

enum TodayWorkoutState: Equatable {
    case noRoutine
    case rest
    case flexible
    case planned(title: String, exerciseCount: Int, minutes: Int?)
    case completed(title: String, sets: Int, seconds: Double, volumeKG: Double)
}
struct HomeWorkoutInput {
    var hasRoutine = false
    var isRestDay = false
    var plannedTitle: String?
    var exerciseCount = 0
    var minutes: Int?
    var completion: (title: String, sets: Int, seconds: Double, volumeKG: Double)?
}
enum HomeStateResolver {
    static func workout(_ input: HomeWorkoutInput) -> TodayWorkoutState {
        if !input.hasRoutine { return .noRoutine }
        if let c = input.completion { return .completed(title: c.title, sets: c.sets, seconds: c.seconds, volumeKG: c.volumeKG) }
        if input.isRestDay { return .rest }
        if let title = input.plannedTitle { return .planned(title: title, exerciseCount: input.exerciseCount, minutes: input.minutes) }
        return .flexible
    }
}

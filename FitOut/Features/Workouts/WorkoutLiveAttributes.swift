import Foundation
import ActivityKit

struct WorkoutLiveAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var revision: UUID
        var title: String
        var exercise: String
        var target: String
        var lastSet: String
        var clockStart: Date
        var paused: Bool
        var elapsed: TimeInterval
        var loggedSets: Int
        var totalSets: Int
        var laps: Int
        var lastLap: TimeInterval?
        var setTimerStart: Date?
        var setTimerElapsed: TimeInterval?
        var restUntil: Date?
        var pausedRest: TimeInterval
    }
    var sessionID: UUID
}

enum WorkoutLiveActionError: LocalizedError {
    case invalidCommand, appProcessOnly, unavailable(String)
    var errorDescription: String? {
        switch self {
        case .invalidCommand: "Open FitOut to control the current workout."
        case .appProcessOnly: "Open FitOut to update this workout."
        case .unavailable(let message): message
        }
    }
}

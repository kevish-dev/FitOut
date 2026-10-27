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
        var phase: String? = nil
        var skippedSets: Int? = nil
        var exerciseIndex: Int? = nil
        var exerciseCount: Int? = nil
        var setIndex: Int? = nil
        var exerciseSetCount: Int? = nil
        var prescription: String? = nil
        var restStartedAt: Date? = nil
    }
    var sessionID: UUID
}

/// Shared, testable display decisions; older ActivityKit payloads still decode.
struct WorkoutLivePresentation {
    enum Action: Equatable { case open, startSet, endRest }
    let state: WorkoutLiveAttributes.ContentState
    let stale: Bool
    let now: Date
    init(state: WorkoutLiveAttributes.ContentState, stale: Bool = false, now: Date = .now) {
        self.state = state; self.stale = stale; self.now = now
    }
    var resting: Bool { state.phase == "resting" || state.restUntil != nil || state.paused && state.pausedRest > 0 }
    var restFinished: Bool { !state.paused && resting && (stale || state.restUntil.map { $0 <= now } == true) }
    var status: String {
        if state.paused { return resting ? "Rest paused" : "Workout paused" }
        if restFinished { return "Rest finished" }
        if resting { return "Rest" }
        switch state.phase {
        case "activeSet": return "In set"
        case "exerciseTransition": return "Next exercise"
        case "workoutCompleted": return "Finished"
        default: return state.totalSets == 0 ? "Set up workout" : "Ready"
        }
    }
    var symbol: String {
        if state.paused { return "pause.fill" }
        if restFinished { return "checkmark" }
        if resting { return "timer" }
        return state.phase == "activeSet" ? "dumbbell.fill" : "figure.strengthtraining.traditional"
    }
    var primaryAction: Action {
        if state.paused { return .open }
        if resting { return .endRest }
        return ["ready", "exerciseTransition"].contains(state.phase ?? "") && state.totalSets > state.loggedSets + max(0, state.skippedSets ?? 0) ? .startSet : .open
    }
    var primaryTitle: String {
        switch primaryAction { case .open: "Open workout"; case .startSet: state.phase == "exerciseTransition" ? "Start exercise" : "Start set"; case .endRest: restFinished ? "Continue" : "Skip rest" }
    }
    var exerciseProgress: String? {
        guard let index = state.exerciseIndex, let count = state.exerciseCount, index > 0, count >= index else { return nil }
        return "\(index)/\(count)"
    }
    var setProgress: String {
        if let index = state.setIndex, let count = state.exerciseSetCount, index > 0, count >= index { return "Set \(index) of \(count)" }
        return "\(max(0, state.loggedSets))/\(max(0, state.totalSets)) sets done"
    }
    var progress: Double {
        guard state.totalSets > 0 else { return 0 }
        return min(1, max(0, Double(state.loggedSets + max(0, state.skippedSets ?? 0)) / Double(state.totalSets)))
    }
    var secondaryDetail: String {
        let target = state.prescription ?? state.target
        return target.isEmpty ? "Open FitOut to configure exercises" : target
    }
    var setTimerVisible: Bool { !resting && (state.phase == "activeSet" || state.paused) && state.setTimerElapsed != nil }
    static func clock(_ seconds: TimeInterval, compact: Bool = false) -> String {
        let bounded = seconds.isFinite ? min(864_000, max(0, seconds)) : 0
        let value = Int(bounded)
        if compact && value >= 3600 { return "\(value / 3600)h" }
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
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

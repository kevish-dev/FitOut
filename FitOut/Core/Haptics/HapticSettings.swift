import Foundation

enum FitHapticEvent: String, Codable, CaseIterable, Identifiable, Sendable {
    case selection, navigation, saved, warning, workoutStarted, setCompleted, setSkipped
    case restEnded, nextSet, nextExercise, pauseResume, workoutCompleted, streak, coachReply
    var id: String { rawValue }
    var title: String {
        switch self {
        case .selection: "Selections & pickers"; case .navigation: "Navigation"
        case .saved: "Saved & logged actions"; case .warning: "Errors & important changes"
        case .workoutStarted: "Workout started"; case .setCompleted: "Set completed"
        case .setSkipped: "Set skipped"; case .restEnded: "Rest timer finished"
        case .nextSet: "Next set started"; case .nextExercise: "Next exercise started"
        case .pauseResume: "Workout pause & resume"; case .workoutCompleted: "Workout completed"
        case .streak: "Streak celebration"; case .coachReply: "Coach reply ready"
        }
    }
    var isWorkout: Bool {
        [.workoutStarted, .setCompleted, .setSkipped, .restEnded, .nextSet, .nextExercise, .pauseResume, .workoutCompleted].contains(self)
    }
    var priority: Int {
        switch self {
        case .restEnded, .workoutCompleted: 3
        case .nextSet, .nextExercise, .warning, .streak: 2
        case .workoutStarted, .setCompleted, .setSkipped, .pauseResume: 1
        default: 0
        }
    }
    var defaults: HapticCueSettings {
        switch self {
        case .selection, .navigation: HapticCueSettings(intensity: 0.3, pulses: 1)
        case .saved, .setCompleted: HapticCueSettings(intensity: 0.6, pulses: 1)
        case .warning: HapticCueSettings(intensity: 0.75, pulses: 2)
        case .restEnded: HapticCueSettings(intensity: 0.9, pulses: 3)
        case .nextExercise, .workoutCompleted: HapticCueSettings(intensity: 0.85, pulses: 3)
        case .workoutStarted, .nextSet, .streak: HapticCueSettings(intensity: 0.7, pulses: 2)
        case .setSkipped, .pauseResume, .coachReply: HapticCueSettings(intensity: 0.45, pulses: 1)
        }
    }
}

enum HapticFeel: String, Codable, CaseIterable, Identifiable, Sendable {
    case soft = "Soft", balanced = "Balanced", crisp = "Crisp"
    var id: String { rawValue }
    var sharpness: Float { switch self { case .soft: 0.15; case .balanced: 0.5; case .crisp: 0.9 } }
}
struct HapticCueSettings: Codable, Equatable, Sendable {
    var enabled = true
    var intensity: Double
    var pulses: Int
    var spacing = 0.22
    var feel: HapticFeel = .balanced
    var isValid: Bool { intensity.isFinite && (0...1).contains(intensity) && (1...5).contains(pulses) && spacing.isFinite && (0.12...0.6).contains(spacing) }
}
struct FitHapticSettings: Codable, Equatable, Sendable {
    var version = 1
    var enabled = true
    var strength = 0.8
    var backgroundRestAlerts = false
    var cues: [FitHapticEvent: HapticCueSettings] = [:]
    func cue(_ event: FitHapticEvent) -> HapticCueSettings { cues[event] ?? event.defaults }
    var isValid: Bool { version == 1 && strength.isFinite && (0...1).contains(strength) && cues.values.allSatisfy(\.isValid) }
    var shouldAlertForRest: Bool { enabled && strength > 0 && backgroundRestAlerts && cue(.restEnded).enabled && cue(.restEnded).intensity > 0 }
}
struct HapticPulse: Equatable, Sendable {
    let time: TimeInterval
    let intensity: Float
    let sharpness: Float
}
enum HapticPatternPolicy {
    static func pulses(for event: FitHapticEvent, settings: FitHapticSettings) -> [HapticPulse] {
        let cue = settings.cue(event)
        guard settings.isValid, settings.enabled, cue.enabled, cue.isValid,
              settings.strength > 0, cue.intensity > 0 else { return [] }
        return (0..<cue.pulses).map { HapticPulse(time: Double($0) * cue.spacing, intensity: Float(settings.strength * cue.intensity), sharpness: cue.feel.sharpness) }
    }
}

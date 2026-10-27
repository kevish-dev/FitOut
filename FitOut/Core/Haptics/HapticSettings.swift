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
        case .selection, .navigation: HapticCueSettings(intensity: 0.65, pulses: 1)
        case .saved, .setCompleted: HapticCueSettings(intensity: 0.85, pulses: 2, duration: 0.12)
        case .warning: HapticCueSettings(intensity: 1, pulses: 3, duration: 0.25)
        case .restEnded: HapticCueSettings(intensity: 1, pulses: 5, spacing: 0.25, duration: 0.45)
        case .nextExercise, .workoutCompleted: HapticCueSettings(intensity: 1, pulses: 4, duration: 0.35)
        case .workoutStarted, .nextSet, .streak: HapticCueSettings(intensity: 0.95, pulses: 3, duration: 0.2)
        case .setSkipped, .pauseResume, .coachReply: HapticCueSettings(intensity: 0.8, pulses: 2, duration: 0.1)
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
    // Optional for existing saved cues: missing duration retains their tap pattern.
    var duration: Double? = nil
    var pulseDuration: Double { duration ?? 0 }
    var isValid: Bool { intensity.isFinite && (0...1).contains(intensity) && (1...10).contains(pulses)
        && spacing.isFinite && (0.12...1).contains(spacing) && pulseDuration.isFinite && (0...0.8).contains(pulseDuration) }
}
enum WorkoutRestAlertMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case notification, alarm
    var id: String { rawValue }
    var title: String { self == .alarm ? "System alarm" : "Notification" }
    func resolved(supportsAlarm: Bool) -> Self { self == .alarm && !supportsAlarm ? .notification : self }
}
struct FitHapticSettings: Codable, Equatable, Sendable {
    var version = 2
    var enabled = true
    var strength = 1.0
    var backgroundRestAlerts = false
    var restAlertMode: WorkoutRestAlertMode = .alarm
    var cues: [FitHapticEvent: HapticCueSettings] = [:]
    init() {}
    private enum CodingKeys: String, CodingKey { case version, enabled, strength, backgroundRestAlerts, restAlertMode, cues }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        guard [1, 2].contains(storedVersion) else { throw DecodingError.dataCorruptedError(forKey: .version, in: values, debugDescription: "Unsupported haptic settings version") }
        enabled = try values.decode(Bool.self, forKey: .enabled)
        strength = try values.decode(Double.self, forKey: .strength)
        backgroundRestAlerts = try values.decode(Bool.self, forKey: .backgroundRestAlerts)
        // Existing notification opt-ins must not silently switch permission types.
        restAlertMode = try values.decodeIfPresent(WorkoutRestAlertMode.self, forKey: .restAlertMode) ?? .notification
        cues = try values.decode([FitHapticEvent: HapticCueSettings].self, forKey: .cues)
    }
    func cue(_ event: FitHapticEvent) -> HapticCueSettings { cues[event] ?? event.defaults }
    mutating func useStrongWorkoutCues() {
        strength = 1
        for event in FitHapticEvent.allCases where event.isWorkout || event == .streak { cues[event] = event.defaults }
    }
    var isValid: Bool { version == 2 && strength.isFinite && (0...1).contains(strength) && cues.values.allSatisfy(\.isValid) }
    var shouldAlertForRest: Bool { enabled && strength > 0 && backgroundRestAlerts && cue(.restEnded).enabled && cue(.restEnded).intensity > 0 }
}
struct HapticPulse: Equatable, Sendable {
    let time: TimeInterval
    let intensity: Float
    let sharpness: Float
    var duration: TimeInterval = 0
    var endTime: TimeInterval { time + duration }
}
enum HapticPatternPolicy {
    static func pulses(for event: FitHapticEvent, settings: FitHapticSettings) -> [HapticPulse] {
        let cue = settings.cue(event)
        guard settings.isValid, settings.enabled, cue.enabled, cue.isValid,
              settings.strength > 0, cue.intensity > 0 else { return [] }
        return (0..<cue.pulses).map { HapticPulse(time: Double($0) * (cue.pulseDuration + cue.spacing),
            intensity: Float(settings.strength * cue.intensity), sharpness: cue.feel.sharpness, duration: cue.pulseDuration) }
    }
}

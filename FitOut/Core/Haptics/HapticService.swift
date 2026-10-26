import SwiftUI
import CoreHaptics
import UIKit
import Observation

@MainActor protocol HapticPlaying {
    var supported: Bool { get }
    func play(_ pulses: [HapticPulse])
    func stop()
}

@MainActor final class DeviceHapticPlayer: HapticPlaying {
    var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?
    private var fallback: Task<Void, Never>?
    func play(_ pulses: [HapticPulse]) {
        stop()
        guard !pulses.isEmpty else { return }
        if supported {
            do {
                if engine == nil {
                    let value = try CHHapticEngine()
                    value.playsHapticsOnly = true; value.isAutoShutdownEnabled = true
                    value.resetHandler = { [weak self] in Task { @MainActor in self?.engine = nil; self?.player = nil } }
                    value.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.player = nil } }
                    engine = value
                }
                guard let engine else { return }
                try engine.start()
                let events = pulses.map { CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: $0.intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: $0.sharpness)
                ], relativeTime: $0.time) }
                player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
                try player?.start(atTime: CHHapticTimeImmediate)
                return
            } catch { engine = nil; player = nil }
        }
        // UIKit is a best-effort fallback; simulators still cannot physically vibrate.
        fallback = Task {
            let generator = UIImpactFeedbackGenerator(style: .light)
            var previous = 0.0
            for pulse in pulses {
                do { try await Task.sleep(for: .seconds(max(0, pulse.time - previous))) } catch { return }
                guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
                generator.impactOccurred(intensity: CGFloat(pulse.intensity)); previous = pulse.time
            }
        }
    }
    func stop() { fallback?.cancel(); fallback = nil; try? player?.stop(atTime: CHHapticTimeImmediate); player = nil }
    func suspend() { stop(); engine?.stop(completionHandler: nil) }
}

@MainActor @Observable final class HapticService {
    static let storageKey = "fitout.haptics.settings.v1"
    private(set) var settings: FitHapticSettings
    private(set) var error: String?
    var onSettingsChange: (() -> Void)?
    var supported: Bool { output.supported }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let repository: any PreferencesRepository
    @ObservationIgnored private let output: any HapticPlaying
    @ObservationIgnored private let playbackEnabled: Bool
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var lastEvent: FitHapticEvent?
    @ObservationIgnored private var lastPlayed = Date.distantPast
    @ObservationIgnored private var importantUntil = Date.distantPast

    init(defaults: UserDefaults, repository: any PreferencesRepository, output: (any HapticPlaying)? = nil, playbackEnabled: Bool = true) {
        self.defaults = defaults; self.repository = repository; self.output = output ?? DeviceHapticPlayer(); self.playbackEnabled = playbackEnabled
        var loaded = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode(FitHapticSettings.self, from: $0) }.flatMap { $0.isValid ? $0 : nil } ?? FitHapticSettings()
        loaded.enabled = ((try? repository.loadPreferences().hapticsEnabled) ?? true) && !defaults.bool(forKey: "haptics.disabled")
        settings = loaded
    }
    @discardableResult func update(_ value: FitHapticSettings) -> Bool {
        guard value.isValid else { error = "Choose an intensity from 0–100%, 1–5 pulses and 0.12–0.60 seconds between pulses."; return false }
        do {
            let encoded = try JSONEncoder().encode(value)
            var preferences = try repository.loadPreferences(); preferences.hapticsEnabled = value.enabled
            try repository.savePreferences(preferences)
            defaults.set(encoded, forKey: Self.storageKey)
            defaults.removeObject(forKey: "haptics.disabled")
            output.stop(); importantUntil = .distantPast; lastPlayed = .distantPast
            settings = value; error = nil; onSettingsChange?(); return true
        } catch { self.error = "Haptic settings could not be saved. Your previous settings are still active."; return false }
    }
    func setEnabled(_ enabled: Bool) { var next = settings; next.enabled = enabled; _ = update(next) }
    func setCue(_ cue: HapticCueSettings, for event: FitHapticEvent) { var next = settings; next.cues[event] = cue; _ = update(next) }
    func sceneChanged(active: Bool) {
        foreground = active
        if !active { output.stop(); (output as? DeviceHapticPlayer)?.suspend(); importantUntil = .distantPast }
    }
    func preview(_ event: FitHapticEvent, cue: HapticCueSettings) {
        guard playbackEnabled, foreground else { return }
        var proposed = settings; proposed.cues[event] = cue
        let pulses = HapticPatternPolicy.pulses(for: event, settings: proposed)
        guard !pulses.isEmpty else { return }
        output.play(pulses)
        lastEvent = event; lastPlayed = .now
        importantUntil = Date().addingTimeInterval((pulses.last?.time ?? 0) + 0.08)
    }
    func play(_ event: FitHapticEvent, preview: Bool = false, now: Date = .now) {
        guard playbackEnabled, foreground else { return }
        let pulses = HapticPatternPolicy.pulses(for: event, settings: settings)
        guard !pulses.isEmpty else { return }
        let interaction = [.selection, .navigation, .saved].contains(event)
        if !preview {
            if interaction && now < importantUntil { return }
            if now < importantUntil, let lastEvent, event.priority < lastEvent.priority { return }
            if event == lastEvent && now.timeIntervalSince(lastPlayed) < (interaction ? 0.08 : 0.15) { return }
        }
        output.play(pulses); lastEvent = event; lastPlayed = now
        if !interaction { importantUntil = now.addingTimeInterval((pulses.last?.time ?? 0) + 0.08) }
    }
}

private struct FitHapticsKey: EnvironmentKey { static let defaultValue: HapticService? = nil }
extension EnvironmentValues {
    var fitHaptics: HapticService? { get { self[FitHapticsKey.self] } set { self[FitHapticsKey.self] = newValue } }
}

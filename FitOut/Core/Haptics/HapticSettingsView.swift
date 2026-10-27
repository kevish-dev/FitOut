import SwiftUI

struct HapticSettingsView: View {
    @Bindable var haptics: HapticService
    @Bindable var workouts: WorkoutHapticCoordinator
    @State private var strength = 1.0
    @State private var resetting = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Form {
            Section {
                Toggle("FitOut haptics", isOn: Binding(get: { haptics.settings.enabled }, set: { haptics.setEnabled($0) }))
                    .accessibilityIdentifier("hapticsMasterToggle")
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Overall intensity", value: strength.formatted(.percent.precision(.fractionLength(0))))
                    Slider(value: $strength, in: 0...1, step: 0.05) { Text("Overall haptic intensity") } onEditingChanged: { editing in
                        if !editing { saveStrength() }
                    }.accessibilityValue(strength.formatted(.percent))
                }.disabled(!haptics.settings.enabled)
                Button("Preview current intensity", systemImage: "waveform") { saveStrength(); haptics.play(.restEnded, preview: true) }
                    .disabled(!haptics.settings.enabled || !haptics.supported || strength == 0)
                Button("Use strong workout vibrations", systemImage: "waveform.path") {
                    var next = haptics.settings; next.useStrongWorkoutCues()
                    if haptics.update(next) { strength = next.strength; haptics.play(.restEnded, preview: true) }
                }.disabled(!haptics.settings.enabled)
            } footer: { Text("Strong workout cues use sustained vibration bursts. Overall intensity scales every cue; zero is silent. Customize intensity, 1–10 pulses, pulse length, spacing and feel below.") }
            Section("Workout cues") {
                ForEach(FitHapticEvent.allCases.filter(\.isWorkout)) { cueRow($0) }
            }.disabled(!haptics.settings.enabled)
            Section("Across the app") {
                ForEach(FitHapticEvent.allCases.filter { !$0.isWorkout }) { cueRow($0) }
            }.disabled(!haptics.settings.enabled)
            Section {
                Picker("Rest alert type", selection: Binding(get: { workouts.alertMode }, set: { mode in Task { await workouts.setAlertMode(mode) } })) {
                    Text("Notification").tag(WorkoutRestAlertMode.notification)
                    if workouts.supportsAlarm { Text("System alarm").tag(WorkoutRestAlertMode.alarm) }
                }.disabled(workouts.isRequesting)
                Toggle("Background rest alerts", isOn: Binding(get: { haptics.settings.backgroundRestAlerts }, set: { value in Task { await workouts.setBackgroundAlerts(value) } }))
                    .disabled(!haptics.settings.enabled || workouts.isRequesting)
                if workouts.isRequesting { ProgressView("Updating rest alert access…") }
                if haptics.settings.backgroundRestAlerts && !workouts.alertsAuthorized {
                    Text(workouts.alertMode == .alarm ? "Alarm access is not enabled. Review FitOut alarms in iPhone Settings." : "Notifications are not enabled. Review FitOut notifications in iPhone Settings.").foregroundStyle(FitTheme.textSecondary)
                }
                if haptics.settings.backgroundRestAlerts && !haptics.settings.shouldAlertForRest {
                    Text("Rest alerts are off while overall intensity is zero or the rest-finished cue is disabled or silent.").foregroundStyle(FitTheme.textSecondary)
                }
                if let error = workouts.error { Text(error).foregroundStyle(FitTheme.textSecondary) }
            } header: { Text("When FitOut is in the background") }
            footer: {
                Text(workouts.alertMode == .alarm
                    ? "System alarms (iOS 26+) alert when rest ends while FitOut is in the background or the screen is locked, including Silent mode and Focus. The alarm can make sound. iOS controls its vibration strength and pattern; dismiss it or open your workout to stop it. While FitOut is open, your custom vibration plays instead."
                    : "Notifications can alert while FitOut is in the background or the screen is locked. iOS notification, sound, vibration and Focus settings control delivery. Custom vibration intensity and pulse length apply while FitOut is open.")
                Text("Pausing, extending or skipping rest, ending the workout or turning haptics off cancels or updates the alert.")
                if !workouts.supportsAlarm { Text("Persistent system rest alarms require iOS 26 or later.") }
            }
            if let error = haptics.error { Section { Text(error).foregroundStyle(FitTheme.textSecondary) } }
            Section {
                Button("Reset haptic defaults", role: .destructive) { resetting = true }
            } footer: {
                Text(haptics.supported ? "These settings control FitOut-generated feedback. Native iOS controls and system notifications can provide their own feedback." : "Haptic previews need a compatible physical iPhone. Settings still save on this device.")
            }
        }
        .nutritionForm().navigationTitle("Haptics & vibration")
        .onAppear { strength = haptics.settings.strength }
        .task(id: phase) { if phase == .active { await workouts.refreshAuthorization() } }
        .confirmationDialog("Reset all haptic settings?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset defaults", role: .destructive) { if haptics.update(FitHapticSettings()) { strength = haptics.settings.strength } }
        } message: { Text("This restores default cues and intensity, enables FitOut haptics and turns background rest alerts off.") }
    }
    private func saveStrength() {
        guard strength != haptics.settings.strength else { return }
        var next = haptics.settings; next.strength = strength
        if !haptics.update(next) { strength = haptics.settings.strength }
    }
    private func cueRow(_ event: FitHapticEvent) -> some View {
        NavigationLink {
            HapticCueEditor(haptics: haptics, event: event)
        } label: {
            LabeledContent(event.title) {
                let cue = haptics.settings.cue(event)
                Text(cue.enabled && cue.intensity > 0 ? "\(cue.pulses) \(cue.pulses == 1 ? "pulse" : "pulses") · \(cue.intensity.formatted(.percent.precision(.fractionLength(0))))" : "Off")
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }.frame(minHeight: 44)
        }
    }
}

private struct HapticCueEditor: View {
    @Bindable var haptics: HapticService
    let event: FitHapticEvent
    @State private var cue = HapticCueSettings(intensity: 0.5, pulses: 1)
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section { Toggle("Enable this cue", isOn: $cue.enabled) }
            Section {
                LabeledContent("Cue intensity", value: cue.intensity.formatted(.percent.precision(.fractionLength(0))))
                Slider(value: $cue.intensity, in: 0...1, step: 0.05).accessibilityLabel("Cue intensity").accessibilityValue(cue.intensity.formatted(.percent))
                Stepper("\(cue.pulses) \(cue.pulses == 1 ? "pulse" : "pulses")", value: $cue.pulses, in: 1...10)
                LabeledContent("Pulse length", value: cue.pulseDuration == 0 ? "Tap" : cue.pulseDuration.formatted(.number.precision(.fractionLength(2))) + " sec")
                Slider(value: Binding(get: { cue.pulseDuration }, set: { cue.duration = $0 }), in: 0...0.8, step: 0.05)
                    .accessibilityLabel("Vibration pulse length").accessibilityValue(cue.pulseDuration.formatted() + " seconds")
                LabeledContent("Between pulses", value: cue.spacing.formatted(.number.precision(.fractionLength(2))) + " sec")
                Slider(value: $cue.spacing, in: 0.12...1, step: 0.04).accessibilityLabel("Time between pulses").accessibilityValue(cue.spacing.formatted() + " seconds")
                Picker("Feel", selection: $cue.feel) { ForEach(HapticFeel.allCases) { Text($0.rawValue).tag($0) } }
                Button("Preview this pattern", systemImage: "waveform") { haptics.preview(event, cue: cue) }
                    .disabled(!haptics.supported || !haptics.settings.enabled || cue.intensity == 0 || haptics.settings.strength == 0)
            }.disabled(!cue.enabled)
            Section {
                Text("Zero pulse length gives a tap; longer pulses give sustained vibration. Preview includes overall intensity. These patterns apply while FitOut is open; iOS controls system alarm and notification vibrations.")
                if let error = haptics.error { Text(error).foregroundStyle(FitTheme.textSecondary) }
            }
        }.nutritionForm().navigationTitle(event.title).navigationBarTitleDisplayMode(.inline)
            .onAppear { cue = haptics.settings.cue(event) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") {
                var next = haptics.settings; next.cues[event] = cue
                if haptics.update(next) { dismiss() }
            }.disabled(!cue.isValid) } }
    }
}

import SwiftUI
import UserNotifications
import Observation

@MainActor @Observable final class HydrationReminderStore {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let identifier = "fitout.water.daily"
    private(set) var enabled: Bool
    private(set) var hour: Int
    private(set) var minute: Int
    private(set) var busy = false
    private(set) var blocked = false
    var error: String?
    init(defaults: UserDefaults, center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults; self.center = center
        enabled = defaults.bool(forKey: "water.reminder.enabled")
        hour = defaults.object(forKey: "water.reminder.hour") as? Int ?? 14
        minute = defaults.object(forKey: "water.reminder.minute") as? Int ?? 0
    }
    func refreshStatus() async {
        let settings = await center.notificationSettings()
        blocked = settings.authorizationStatus == .denied
    }
    func set(enabled: Bool, time: Date) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        if !enabled {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            self.enabled = false; defaults.set(false, forKey: "water.reminder.enabled"); return
        }
        do {
            let settings = await center.notificationSettings()
            let granted: Bool
            if settings.authorizationStatus == .notDetermined { granted = try await center.requestAuthorization(options: [.alert, .sound]) }
            else { granted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional || settings.authorizationStatus == .ephemeral }
            guard granted else { blocked = true; error = "Notifications are disabled for FitOut. Review them in iPhone Settings to enable a reminder."; return }
            blocked = false
            let components = Calendar.current.dateComponents([.hour, .minute], from: time)
            let content = UNMutableNotificationContent()
            content.title = "Water check-in"
            content.body = "Take a moment to log any water you've had in FitOut."
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            try await center.add(request)
            hour = components.hour ?? 14; minute = components.minute ?? 0; self.enabled = true
            defaults.set(true, forKey: "water.reminder.enabled"); defaults.set(hour, forKey: "water.reminder.hour"); defaults.set(minute, forKey: "water.reminder.minute")
        } catch { self.error = error.localizedDescription }
    }
}

struct HydrationReminderView: View {
    let store: HydrationReminderStore
    @State private var enabled = false
    @State private var time = Date()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Form {
            Section {
                Toggle("Daily water check-in", isOn: $enabled)
                if enabled { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                Button(store.busy ? "Saving…" : "Save reminder") { Task { await store.set(enabled: enabled, time: time) } }.disabled(store.busy)
            } footer: { Text("One optional local reminder each day at your chosen time. Notification permission is requested only when you save an enabled reminder.") }
            if store.enabled { Label(store.blocked ? "Notifications disabled in Settings" : "Reminder scheduled", systemImage: store.blocked ? "bell.slash" : "bell.badge").font(FitTheme.body(13)) }
            if let error = store.error { Text(error).font(FitTheme.body(13)).foregroundStyle(.orange) }
        }.nutritionForm().navigationTitle("Water reminder")
        .onAppear {
            enabled = store.enabled
            time = Calendar.current.date(bySettingHour: store.hour, minute: store.minute, second: 0, of: .now) ?? .now
        }
        .task(id: phase) { if phase == .active { await store.refreshStatus() } }
    }
}

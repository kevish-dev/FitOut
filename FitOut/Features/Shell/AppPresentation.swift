import SwiftUI
import Observation

enum AppNavigationStyle: String, CaseIterable, Identifiable {
    case topRight, bottomBar
    var id: String { rawValue }
    var title: String { self == .topRight ? "Top-right menu" : "Bottom bar" }
}

enum AppSection: Int, CaseIterable, Identifiable {
    case home, gym, nutrition, health, coach
    var id: Int { rawValue }
    var title: String {
        switch self { case .home: "Home"; case .gym: "Gym"; case .nutrition: "Nutrition"; case .health: "Health"; case .coach: "AI Coach" }
    }
    var symbol: String {
        switch self { case .home: "house"; case .gym: "dumbbell"; case .nutrition: "fork.knife"; case .health: "heart"; case .coach: "sparkles" }
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .dark: .dark; case .light: .light }
    }
}

@MainActor @Observable final class AppPresentationPreferences {
    private let repository: any PreferencesRepository
    private let defaults: UserDefaults
    private(set) var navigationStyle: AppNavigationStyle
    private(set) var appearance: AppAppearance
    private(set) var error: String?
    var onChange: (() -> Void)?
    static let navigationKey = "fitout.navigation.style"
    init(repository: any PreferencesRepository, defaults: UserDefaults) throws {
        self.repository = repository; self.defaults = defaults
        appearance = try repository.loadPreferences().appearance
        navigationStyle = defaults.string(forKey: Self.navigationKey).flatMap(AppNavigationStyle.init(rawValue:)) ?? .topRight
    }
    func selectNavigation(_ value: AppNavigationStyle) {
        defaults.set(value.rawValue, forKey: Self.navigationKey)
        navigationStyle = value; onChange?()
    }
    @discardableResult func selectAppearance(_ value: AppAppearance) -> Bool {
        do {
            var saved = try repository.loadPreferences()
            saved.appearance = value
            try repository.savePreferences(saved)
            appearance = value; error = nil; onChange?(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

private struct AppNavigationStyleKey: EnvironmentKey { static let defaultValue = AppNavigationStyle.topRight }
extension EnvironmentValues {
    var appNavigationStyle: AppNavigationStyle {
        get { self[AppNavigationStyleKey.self] }
        set { self[AppNavigationStyleKey.self] = newValue }
    }
}

struct ProfilePresentationSection: View {
    let preferences: AppPresentationPreferences
    var body: some View {
        Section {
            ForEach(AppNavigationStyle.allCases) { style in
                Button { preferences.selectNavigation(style) } label: {
                    HStack(spacing: 14) {
                        layoutPreview(style)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(style.title).font(FitTheme.section(14)).foregroundStyle(FitTheme.textPrimary)
                            Text(style == .bottomBar ? "Five destinations, always within reach." : "Expand the menu in the upper corner.")
                                .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: preferences.navigationStyle == style ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(preferences.navigationStyle == style ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                    }.frame(minHeight: 72).contentShape(Rectangle())
                }.buttonStyle(.fitPlain)
                    .accessibilityLabel(style.title).accessibilityAddTraits(preferences.navigationStyle == style ? .isSelected : [])
                    .accessibilityIdentifier("navigationStyle-\(style.rawValue)")
            }
        } header: { Text("App navigation") } footer: { Text("Changes apply immediately and are saved on this iPhone.") }
        Section("Appearance") {
            Picker("Theme", selection: Binding(get: { preferences.appearance }, set: { _ = preferences.selectAppearance($0) })) {
                Text("System").tag(AppAppearance.system)
                Text("Light").tag(AppAppearance.light)
                Text("Dark").tag(AppAppearance.dark)
            }.pickerStyle(.segmented).accessibilityIdentifier("appAppearancePicker")
            if let error = preferences.error { Text(error).foregroundStyle(.red) }
        }
    }
    private func layoutPreview(_ style: AppNavigationStyle) -> some View {
        ZStack(alignment: style == .bottomBar ? .bottom : .topTrailing) {
            RoundedRectangle(cornerRadius: 12).fill(FitTheme.dashboardBackground)
            if style == .bottomBar {
                HStack(spacing: 4) { ForEach(0..<5) { _ in Circle().fill(FitTheme.textSecondary.opacity(0.5)).frame(width: 5, height: 5) } }
                    .frame(width: 40, height: 14).background(FitTheme.elevated, in: Capsule()).padding(6)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 7))
                    Circle().frame(width: 5, height: 5)
                    Circle().frame(width: 5, height: 5)
                }.foregroundStyle(FitTheme.textSecondary).padding(7)
            }
        }.frame(width: 56, height: 68).overlay { RoundedRectangle(cornerRadius: 12).stroke(FitTheme.subtleBorder) }.accessibilityHidden(true)
    }
}

/// System selection callbacks may repeat during layout/sheet presentation.
/// Only an explicit corner-menu reselect is allowed to replace a section root.
struct AppTabNavigation {
    enum Source { case system, menu }
    var selected = AppSection.home.rawValue
    private(set) var revisions: [Int: UUID] = [:]
    mutating func select(_ destination: Int, source: Source) {
        guard AppSection(rawValue: destination) != nil else { return }
        guard destination != selected else {
            if source == .menu { revisions[destination] = UUID() }
            return
        }
        selected = destination
    }
}

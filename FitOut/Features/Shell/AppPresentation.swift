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

struct BottomAppNavigation: View {
    let selection: Int
    let select: (Int) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppSection.allCases.filter { $0 != .coach }) { destination in item(destination) }
            }
            .padding(5)
            .dashboardGlass(in: Capsule(), interactive: true)
            item(.coach).frame(width: 64, height: 64)
                .dashboardGlass(in: Circle(), highlighted: selection == AppSection.coach.rawValue, interactive: true)
        }
        .frame(maxWidth: 560).padding(.horizontal, FitTheme.pageInset).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain).accessibilityLabel("Main navigation")
        .accessibilityIdentifier("bottomNavigationBar")
    }
    private func item(_ destination: AppSection) -> some View {
        let selected = selection == destination.rawValue
        return Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { select(destination.rawValue) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: destination.symbol).font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? FitTheme.dashboardAccent : FitTheme.textPrimary)
                if !typeSize.isAccessibilitySize {
                    Text(destination.title).font(FitTheme.medium(10)).lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(selected ? FitTheme.textPrimary : FitTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(selected && destination != .coach ? FitTheme.textPrimary.opacity(0.07) : .clear, in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(.plain)
            .accessibilityLabel(destination.title).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("navigate-\(destination.rawValue)")
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
                }.buttonStyle(.plain)
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
                HStack(spacing: 4) { ForEach(0..<4) { _ in Circle().fill(FitTheme.textSecondary.opacity(0.5)).frame(width: 5, height: 5) } }
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

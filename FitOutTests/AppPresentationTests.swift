import XCTest
import SwiftUI
import UIKit
@testable import FitOut

final class AppPresentationTests: XCTestCase {
    @MainActor func testNavigationPersistsAndInvalidValuesKeepExistingTopRightDefault() throws {
        let name = "navigation-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = SwiftDataRepository(container: try PersistenceFactory.makeContainer(inMemory: true))
        let preferences = try AppPresentationPreferences(repository: repository, defaults: defaults)
        XCTAssertEqual(preferences.navigationStyle, .topRight)
        preferences.selectNavigation(.bottomBar)
        XCTAssertEqual(try AppPresentationPreferences(repository: repository, defaults: defaults).navigationStyle, .bottomBar)
        preferences.selectNavigation(.topRight)
        XCTAssertEqual(try AppPresentationPreferences(repository: repository, defaults: defaults).navigationStyle, .topRight)
        defaults.set("obsolete-layout", forKey: AppPresentationPreferences.navigationKey)
        XCTAssertEqual(try AppPresentationPreferences(repository: repository, defaults: defaults).navigationStyle, .topRight)
    }

    @MainActor func testAppearanceUsesSavedRepositoryAndPreservesOtherPreferences() throws {
        let name = "appearance-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = SwiftDataRepository(container: try PersistenceFactory.makeContainer(inMemory: true))
        try repository.savePreferences(AppPreferences(appearance: .dark, hapticsEnabled: false))
        let preferences = try AppPresentationPreferences(repository: repository, defaults: defaults)
        var updates = 0
        preferences.onChange = { updates += 1 }
        XCTAssertTrue(preferences.selectAppearance(.light))
        XCTAssertEqual(preferences.appearance.colorScheme, .light)
        XCTAssertEqual(try repository.loadPreferences(), AppPreferences(appearance: .light, hapticsEnabled: false))
        XCTAssertEqual(try AppPresentationPreferences(repository: repository, defaults: defaults).appearance, .light)
        XCTAssertTrue(preferences.selectAppearance(.system))
        XCTAssertNil(preferences.appearance.colorScheme)
        XCTAssertEqual(try repository.loadPreferences().appearance, .system)
        XCTAssertEqual(updates, 2)
    }

    @MainActor func testFailedAppearanceSaveDoesNotChangeDisplayedTheme() throws {
        let name = "failed-theme-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let repository = FailingPresentationRepository()
        let preferences = try AppPresentationPreferences(repository: repository, defaults: defaults)
        XCTAssertFalse(preferences.selectAppearance(.light))
        XCTAssertEqual(preferences.appearance, .dark)
        XCTAssertNotNil(preferences.error)
        XCTAssertEqual(repository.value.appearance, .dark)
    }

    func testNavigationContainsExactlyTheExistingFiveDestinations() {
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
        XCTAssertEqual(AppSection.allCases.map(\.title), ["Home", "Gym", "Nutrition", "Health", "AI Coach"])
        XCTAssertEqual(Set(AppSection.allCases.map(\.symbol)).count, 5)
    }

    @MainActor func testAdaptiveTextAndSurfacesHaveReadableContrastInBothAppearances() {
        func luminance(_ color: Color, style: UIUserInterfaceStyle) -> Double {
            let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
            func linear(_ component: CGFloat) -> Double {
                let v = Double(component)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let text = luminance(FitTheme.textPrimary, style: style)
            for background in [FitTheme.surface, FitTheme.dashboardBackground, FitTheme.elevated] {
                let surface = luminance(background, style: style)
                XCTAssertGreaterThan((max(text, surface) + 0.05) / (min(text, surface) + 0.05), 4.5)
            }
        }
    }
}

@MainActor private final class FailingPresentationRepository: PreferencesRepository {
    var value = AppPreferences()
    func loadPreferences() throws -> AppPreferences { value }
    func savePreferences(_ preferences: AppPreferences) throws { throw CocoaError(.fileWriteNoPermission) }
}

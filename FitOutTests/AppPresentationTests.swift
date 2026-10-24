import XCTest
import SwiftUI
import UIKit
@testable import FitOut

final class AppPresentationTests: XCTestCase {
    func testRepeatedNativeTabCallbacksCannotReplaceGymRootDuringSheetPresentation() {
        var navigation = AppTabNavigation()
        navigation.select(AppSection.gym.rawValue, source: .system)
        for _ in 0..<100 { navigation.select(AppSection.gym.rawValue, source: .system) }
        XCTAssertEqual(navigation.selected, AppSection.gym.rawValue)
        XCTAssertTrue(navigation.revisions.isEmpty)
        navigation.select(AppSection.home.rawValue, source: .system)
        navigation.select(AppSection.gym.rawValue, source: .system)
        XCTAssertTrue(navigation.revisions.isEmpty)
    }

    func testExplicitMenuReselectResetsOnlyRequestedRootAndSystemEchoPreservesIt() {
        var navigation = AppTabNavigation()
        navigation.select(AppSection.gym.rawValue, source: .menu)
        XCTAssertTrue(navigation.revisions.isEmpty)
        navigation.select(AppSection.gym.rawValue, source: .menu)
        let revision = navigation.revisions[AppSection.gym.rawValue]
        XCTAssertNotNil(revision)
        navigation.select(AppSection.gym.rawValue, source: .system)
        XCTAssertEqual(navigation.revisions[AppSection.gym.rawValue], revision)
        navigation.select(AppSection.home.rawValue, source: .menu)
        XCTAssertEqual(navigation.revisions[AppSection.gym.rawValue], revision)
        navigation.select(99, source: .system)
        XCTAssertEqual(navigation.selected, AppSection.home.rawValue)
    }

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

    func testFloatingControlStaysInsideSafeEdgesOnCompactAndLandscapeScreens() throws {
        for viewport in [CGRect(x: 0, y: 0, width: 390, height: 844), CGRect(x: 0, y: 0, width: 844, height: 390)] {
            let geometry = FloatingWorkoutGeometry(viewport: viewport, safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), size: CGSize(width: 238, height: 60))
            for center in [CGPoint(x: -500, y: -500), CGPoint(x: 2000, y: 2000)] {
                let frame = try XCTUnwrap(geometry.frame(near: center))
                XCTAssertTrue(geometry.region.contains(frame))
            }
            for right in [false, true] {
                let center = geometry.preferredCenter(right: right, fraction: 0.68)
                XCTAssertEqual(geometry.verticalFraction(for: center), 0.68, accuracy: 0.001)
            }
        }
    }

    func testFloatingControlClearsNativeTabBarAndPinnedComposer() throws {
        let tabBar = CGRect(x: 0, y: 744, width: 390, height: 100)
        let composer = CGRect(x: 0, y: 642, width: 390, height: 102)
        let geometry = FloatingWorkoutGeometry(viewport: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), size: CGSize(width: 238, height: 60), obstructions: [tabBar, composer])
        let frame = try XCTUnwrap(geometry.frame(near: CGPoint(x: 260, y: 800)))
        XCTAssertLessThanOrEqual(frame.maxY, composer.minY - 12)
        XCTAssertFalse(frame.intersects(tabBar))
        XCTAssertFalse(frame.intersects(composer))
    }

    func testFloatingControlClearsKeyboardAndComposerTogether() throws {
        let keyboard = CGRect(x: 0, y: 460, width: 390, height: 384)
        let composer = CGRect(x: 0, y: 354, width: 390, height: 106)
        let geometry = FloatingWorkoutGeometry(viewport: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), size: CGSize(width: 238, height: 60), obstructions: [keyboard, composer])
        let frame = try XCTUnwrap(geometry.frame(near: CGPoint(x: 260, y: 600)))
        XCTAssertLessThanOrEqual(frame.maxY, composer.minY - 12)
        XCTAssertTrue(geometry.region.contains(frame))
    }

    func testFloatingControlCanMoveBesideFloatingKeyboard() throws {
        let keyboard = CGRect(x: 480, y: 600, width: 300, height: 300)
        let geometry = FloatingWorkoutGeometry(viewport: CGRect(x: 0, y: 0, width: 1024, height: 1366),
            safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0), size: CGSize(width: 238, height: 60), obstructions: [keyboard])
        let frame = try XCTUnwrap(geometry.frame(near: CGPoint(x: 600, y: 730)))
        XCTAssertFalse(frame.intersects(keyboard.insetBy(dx: -12, dy: -12)))
        XCTAssertTrue(geometry.region.contains(frame))
    }

    func testFloatingControlHidesWhenAccessibilitySizeAndKeyboardLeaveNoSpace() {
        var geometry = FloatingWorkoutGeometry(viewport: CGRect(x: 0, y: 0, width: 320, height: 568),
            safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0), size: CGSize(width: 238, height: 180),
            obstructions: [CGRect(x: 0, y: 190, width: 320, height: 378)])
        XCTAssertNil(geometry.frame(near: .zero))
        geometry.obstructions = []
        XCTAssertNotNil(geometry.frame(near: .zero))
    }

    func testFloatingControlRecoversFromInvalidCoordinatesAndRejectsInvalidSize() throws {
        var geometry = FloatingWorkoutGeometry(viewport: CGRect(x: 0, y: 0, width: 390, height: 844),
            safeArea: .zero, size: CGSize(width: 238, height: 60))
        let frame = try XCTUnwrap(geometry.frame(near: CGPoint(x: CGFloat.nan, y: CGFloat.infinity)))
        XCTAssertTrue(geometry.region.contains(frame))
        geometry.size.height = .infinity
        XCTAssertNil(geometry.frame(near: .zero))
        geometry.size = CGSize(width: 400, height: 60)
        XCTAssertNil(geometry.frame(near: .zero))
    }

    @MainActor func testWorkoutEditorVisibilityRefreshesControlWithoutSavingSessionData() throws {
        let store = try WorkoutStore(container: PersistenceFactory.makeContainer(inMemory: true))
        var visibilityUpdates = 0, sessionWrites = 0
        store.onEditorVisibilityChange = { visibilityUpdates += 1 }
        store.onChange = { sessionWrites += 1 }
        store.editorAppeared(); store.editorAppeared()
        XCTAssertEqual(store.visibleEditorCount, 2)
        store.editorDisappeared()
        XCTAssertEqual(store.visibleEditorCount, 1)
        store.editorDisappeared(); store.editorDisappeared()
        XCTAssertEqual(store.visibleEditorCount, 0)
        XCTAssertEqual(visibilityUpdates, 5)
        XCTAssertEqual(sessionWrites, 0)
        XCTAssertTrue(store.sessions.isEmpty)
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

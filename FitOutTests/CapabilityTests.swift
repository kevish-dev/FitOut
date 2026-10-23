import XCTest
import HealthKit
@testable import FitOut

final class CapabilityTests: XCTestCase {
    func testEveryUnavailableReasonRemainsUnavailableWithAnExplanation() {
        let reasons: [CapabilityStatus.Reason] = [.requiresOS("26"), .deviceNotEligible, .intelligenceDisabled, .modelNotReady, .systemUnavailable]
        for reason in reasons {
            let status = CapabilityStatus.unavailable(reason)
            XCTAssertFalse(status.isAvailable)
            XCTAssertFalse(status.explanation.isEmpty)
            XCTAssertFalse(status.explanation.lowercased().contains("permission denied"))
        }
        XCTAssertTrue(CapabilityStatus.available.isAvailable)
    }

    @MainActor func testCapabilitiesAreIndependent() {
        let expected = CapabilitySnapshot(healthKit: .available, foundationModels: .unavailable(.intelligenceDisabled), imagePlayground: .unavailable(.systemUnavailable))
        let provider: any RuntimeCapabilityProviding = FixedCapabilityProvider(snapshot: expected)
        XCTAssertEqual(provider.currentCapabilities(), expected)
        XCTAssertTrue(provider.currentCapabilities().healthKit.isAvailable)
        XCTAssertFalse(provider.currentCapabilities().foundationModels.isAvailable)
    }

    func testOverlappingSleepSamplesAreCountedOnce() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let intervals = [
            DateInterval(start: start, duration: 3_600),
            DateInterval(start: start.addingTimeInterval(1_800), duration: 3_600),
            DateInterval(start: start.addingTimeInterval(7_200), duration: 1_800)
        ]
        let merged = HealthAccessService.mergeIntervals(intervals)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.reduce(0) { $0 + $1.duration }, 7_200)
    }

    @MainActor func testExistingHealthAccessIsReadWithoutLocalSetupFlag() async {
        let name = "health-read-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let reader = TestHealthReader()
        reader.values[.steps] = HealthMetricSeries(total: 4_321, buckets: [])
        reader.values[.activeCalories] = HealthMetricSeries(total: 246, buckets: [])
        let service = HealthAccessService(capability: healthProvider(), defaults: defaults, reader: reader)

        XCTAssertFalse(service.hasRequested)
        await service.refreshOverview()
        XCTAssertEqual(service.overview.steps.total, 4_321)
        XCTAssertEqual(service.overview.activeCalories.total, 246)
        XCTAssertEqual(Set(reader.metrics), Set(HealthQuantityMetric.allCases))
        XCTAssertEqual(reader.authorizationRequests, 0) // Reading never opens a permission sheet.
        XCTAssertNotNil(service.lastRefreshedAt)
    }

    @MainActor func testReloadRequeriesAndDisplaysChangedReadingsIncludingZero() async {
        let name = "health-reload-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "health.requested")
        let reader = TestHealthReader()
        let service = HealthAccessService(capability: healthProvider(), defaults: defaults, reader: reader)
        await service.refreshOverview()
        XCTAssertNil(service.overview.steps.total)
        reader.values[.steps] = HealthMetricSeries(total: 5_000, buckets: [])
        reader.values[.activeCalories] = HealthMetricSeries(total: 0, buckets: [])
        await service.refreshOverview()
        XCTAssertEqual(service.overview.steps.total, 5_000)
        XCTAssertEqual(service.overview.activeCalories.total, 0)
        XCTAssertTrue(service.overview.hasAnyReading)
        XCTAssertEqual(reader.metrics.count, 6)
        XCTAssertFalse(service.isRefreshing)
    }

    @MainActor func testReviewingPermissionRefreshesEvenWhenAlreadyRequested() async {
        let name = "health-permission-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "health.requested")
        let reader = TestHealthReader()
        let service = HealthAccessService(capability: healthProvider(), defaults: defaults, reader: reader)
        await service.requestAccess()
        reader.values[.steps] = HealthMetricSeries(total: 123, buckets: [])
        await service.requestAccess()
        XCTAssertEqual(reader.authorizationRequests, 2)
        XCTAssertEqual(reader.metrics.count, 6)
        XCTAssertEqual(service.overview.steps.total, 123)
        XCTAssertTrue(service.hasRequested)
        XCTAssertFalse(service.isRequesting)
    }

    @MainActor func testHealthQueriesUseTheCurrentLocalDayAndActiveEnergy() async {
        let name = "health-date-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 7))!
        let reader = TestHealthReader()
        let service = HealthAccessService(capability: healthProvider(), defaults: defaults, reader: reader)
        await service.refreshOverview(at: now, calendar: calendar)
        XCTAssertTrue(reader.windows.allSatisfy { $0.start == calendar.startOfDay(for: now) && $0.end == now })
        XCTAssertEqual(HealthQuantityMetric.steps.identifier, .stepCount)
        XCTAssertEqual(HealthQuantityMetric.activeCalories.identifier, .activeEnergyBurned)
        XCTAssertEqual(HealthQuantityMetric.activeCalories.unit, .kilocalorie())
    }

    @MainActor func testQueryErrorsStayDistinctFromNoSharedSamples() async {
        let name = "health-error-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let reader = TestHealthReader()
        reader.values[.steps] = HealthMetricSeries(total: nil, buckets: [], errorMessage: "Health data is locked.")
        let service = HealthAccessService(capability: healthProvider(), defaults: defaults, reader: reader)
        await service.refreshOverview()
        XCTAssertEqual(service.overview.queryErrors, ["Steps: Health data is locked."])
        XCTAssertNil(service.overview.activeCalories.errorMessage)
        XCTAssertNil(service.overview.activeCalories.total)
    }

    func testHealthNoDataIsEmptyWhileLockedDataRemainsAnError() {
        let noData = NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)
        let locked = NSError(domain: HKErrorDomain, code: HKError.Code.errorDatabaseInaccessible.rawValue)
        XCTAssertNil(HealthKitDataReader.queryErrorMessage(noData))
        XCTAssertNotNil(HealthKitDataReader.queryErrorMessage(locked))
        XCTAssertNil(HealthKitDataReader.queryErrorMessage(nil))
    }

    @MainActor func testUnavailableHealthDoesNotQueryOrPrompt() async {
        let name = "health-unavailable-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let reader = TestHealthReader()
        let service = HealthAccessService(capability: healthProvider(available: false), defaults: defaults, reader: reader)
        await service.requestAccess()
        await service.refreshOverview()
        XCTAssertTrue(reader.metrics.isEmpty)
        XCTAssertEqual(reader.authorizationRequests, 0)
        XCTAssertFalse(service.overview.hasAnyReading)
        XCTAssertNil(service.lastRefreshedAt)
    }

    @MainActor func testAnOlderReadCannotOverwriteANewerReload() async {
        let name = "health-race-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let reader = TestHealthReader()
        reader.holdSteps = true
        let service = HealthAccessService(capability: healthProvider(), defaults: defaults, reader: reader)
        let olderDate = Date(timeIntervalSince1970: 1_792_800_000)
        let newerDate = olderDate.addingTimeInterval(60)
        let older = Task { await service.refreshOverview(at: olderDate) }
        await reader.waitForSteps(at: olderDate)
        let newer = Task { await service.refreshOverview(at: newerDate) }
        await reader.waitForSteps(at: newerDate)
        reader.completeSteps(at: newerDate, total: 500)
        await newer.value
        reader.completeSteps(at: olderDate, total: 100)
        await older.value
        XCTAssertEqual(service.overview.steps.total, 500)
        XCTAssertEqual(service.lastRefreshedAt, newerDate)
        XCTAssertFalse(service.isRefreshing)
    }

    @MainActor private func healthProvider(available: Bool = true) -> any RuntimeCapabilityProviding {
        FixedCapabilityProvider(snapshot: CapabilitySnapshot(healthKit: available ? .available : .unavailable(.systemUnavailable),
            foundationModels: .unavailable(.systemUnavailable), imagePlayground: .unavailable(.systemUnavailable)))
    }
}

@MainActor private final class TestHealthReader: HealthDataReading {
    var authorizationRequests = 0
    var metrics: [HealthQuantityMetric] = []
    var windows: [(start: Date, end: Date)] = []
    var values: [HealthQuantityMetric: HealthMetricSeries] = [:]
    var holdSteps = false
    private var pending: [Date: CheckedContinuation<HealthMetricSeries, Never>] = [:]
    private var waiting: [Date: CheckedContinuation<Void, Never>] = [:]

    func requestAccess() async throws { authorizationRequests += 1 }
    func quantitySeries(_ metric: HealthQuantityMetric, start: Date, end: Date, calendar: Calendar) async -> HealthMetricSeries {
        metrics.append(metric)
        windows.append((start, end))
        if metric == .steps && holdSteps {
            return await withCheckedContinuation { continuation in
                pending[end] = continuation
                waiting.removeValue(forKey: end)?.resume()
            }
        }
        return values[metric] ?? .empty
    }
    func sleepSeries(at now: Date, calendar: Calendar) async -> HealthMetricSeries { .empty }
    func waitForSteps(at date: Date) async {
        if pending[date] != nil { return }
        await withCheckedContinuation { waiting[date] = $0 }
    }
    func completeSteps(at date: Date, total: Double) {
        pending.removeValue(forKey: date)?.resume(returning: HealthMetricSeries(total: total, buckets: []))
    }
}

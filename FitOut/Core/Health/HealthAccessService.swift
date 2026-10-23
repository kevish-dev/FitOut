import Foundation
import HealthKit
import Observation

struct HealthMetricSeries: Sendable {
    let total: Double?
    let buckets: [Double]
    var errorMessage: String? = nil

    static let empty = HealthMetricSeries(total: nil, buckets: Array(repeating: 0, count: 12))
}

struct HealthOverview: Sendable {
    let waterMilliliters: HealthMetricSeries
    let steps: HealthMetricSeries
    let activeCalories: HealthMetricSeries
    let sleepHours: HealthMetricSeries

    static let empty = HealthOverview(waterMilliliters: .empty, steps: .empty,
                                       activeCalories: .empty, sleepHours: .empty)

    var hasAnyReading: Bool {
        waterMilliliters.total != nil || steps.total != nil ||
        activeCalories.total != nil || sleepHours.total != nil
    }

    var queryErrors: [String] {
        [("Water", waterMilliliters), ("Steps", steps), ("Active calories", activeCalories), ("Sleep", sleepHours)]
            .compactMap { name, series in series.errorMessage.map { "\(name): \($0)" } }
    }
}

enum HealthQuantityMetric: CaseIterable, Hashable, Sendable {
    case water, steps, activeCalories

    var identifier: HKQuantityTypeIdentifier {
        switch self {
        case .water: .dietaryWater
        case .steps: .stepCount
        case .activeCalories: .activeEnergyBurned
        }
    }
    var unit: HKUnit {
        switch self {
        case .water: .literUnit(with: .milli)
        case .steps: .count()
        case .activeCalories: .kilocalorie()
        }
    }
}

@MainActor protocol HealthDataReading: Sendable {
    func requestAccess() async throws
    func quantitySeries(_ metric: HealthQuantityMetric, start: Date, end: Date, calendar: Calendar) async -> HealthMetricSeries
    func sleepSeries(at now: Date, calendar: Calendar) async -> HealthMetricSeries
}

@MainActor @Observable final class HealthAccessService {
    var isRequesting = false
    var error: String?
    var onChange: (() -> Void)?
    private(set) var hasRequested: Bool
    private(set) var overview = HealthOverview.empty
    private(set) var isRefreshing = false
    private(set) var lastRefreshedAt: Date?
    private var refreshGeneration = 0
    private let reader: any HealthDataReading
    private let defaults: UserDefaults
    private let capability: any RuntimeCapabilityProviding
    init(capability: any RuntimeCapabilityProviding, defaults: UserDefaults, reader: (any HealthDataReading)? = nil) {
        self.capability = capability; self.defaults = defaults
        self.reader = reader ?? HealthKitDataReader()
        hasRequested = defaults.bool(forKey: "health.requested")
    }
    var isAvailable: Bool { capability.currentCapabilities().healthKit.isAvailable }
    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>([HKObjectType.workoutType(), HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!])
        for id: HKQuantityTypeIdentifier in [.stepCount, .activeEnergyBurned, .basalEnergyBurned, .bodyMass, .height, .heartRate, .restingHeartRate, .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryWater] {
            if let type = HKObjectType.quantityType(forIdentifier: id) { types.insert(type) }
        }
        return types
    }
    func requestAccess() async {
        guard isAvailable, !isRequesting else { return }
        isRequesting = true; error = nil
        defer { isRequesting = false }
        do {
            try await reader.requestAccess()
            // This records only that the system flow completed, never read authorization.
            hasRequested = true; defaults.set(true, forKey: "health.requested")
            // Permission review can complete with hasRequested already true.
            // Always query again, rather than depending on a Boolean change in Home.
            await refreshOverview()
        } catch { self.error = error.localizedDescription }
    }

    /// Read only data already shared with FitOut. HealthKit intentionally does not
    /// reveal whether a missing reading means no samples or denied read access.
    func todayOverview(at now: Date = .now, calendar: Calendar = .current) async -> HealthOverview {
        // A local preference is not a HealthKit authorization check. Previously
        // granted access must still work after preferences are reset or restored.
        guard isAvailable else { return .empty }
        let start = calendar.startOfDay(for: now)
        async let water = reader.quantitySeries(.water, start: start, end: now, calendar: calendar)
        async let steps = reader.quantitySeries(.steps, start: start, end: now, calendar: calendar)
        async let calories = reader.quantitySeries(.activeCalories, start: start, end: now, calendar: calendar)
        async let sleep = reader.sleepSeries(at: now, calendar: calendar)
        return await HealthOverview(waterMilliliters: water, steps: steps, activeCalories: calories, sleepHours: sleep)
    }

    func refreshOverview(at now: Date = .now, calendar: Calendar = .current) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        if let lastRefreshedAt, !calendar.isDate(lastRefreshedAt, inSameDayAs: now) {
            overview = .empty
        }
        isRefreshing = true
        let result = await todayOverview(at: now, calendar: calendar)
        // An older request must not replace a newer reload or permission review.
        guard generation == refreshGeneration else { return }
        isRefreshing = false
        guard !Task.isCancelled else { return }
        overview = result
        lastRefreshedAt = isAvailable ? now : nil
        onChange?()
    }

    nonisolated static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

@MainActor final class HealthKitDataReader: HealthDataReading {
    private let store = HKHealthStore()

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: HealthAccessService.readTypes)
    }

    func quantitySeries(_ metric: HealthQuantityMetric, start: Date, end: Date, calendar: Calendar) async -> HealthMetricSeries {
        guard end > start, let type = HKObjectType.quantityType(forIdentifier: metric.identifier) else { return .empty }
        let unit = metric.unit
        // The daily number is independent of the decorative two-hour history.
        // A chart-query failure must not hide a valid steps/energy total.
        async let total = quantityTotal(type, unit: unit, start: start, end: end)
        async let buckets = quantityBuckets(type, unit: unit, start: start, end: end, calendar: calendar)
        let result = await total
        return await HealthMetricSeries(total: result.value, buckets: buckets, errorMessage: result.error)
    }

    private func quantityTotal(_ type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async -> (value: Double?, error: String?) {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: (error == nil ? value.map { max(0, $0) } : nil, Self.queryErrorMessage(error)))
            }
            store.execute(query)
        }
    }

    private func quantityBuckets(_ type: HKQuantityType, unit: HKUnit, start: Date, end: Date, calendar: Calendar) async -> [Double] {
        let store = store
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(hour: 2))
            query.initialResultsHandler = { query, collection, error in
                defer { store.stop(query) }
                guard error == nil, let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var buckets = Array(repeating: 0.0, count: 12)
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let hour = calendar.component(.hour, from: statistics.startDate)
                    buckets[hour / 2] += max(0, quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: buckets)
            }
            store.execute(query)
        }
    }

    func sleepSeries(at now: Date, calendar: Calendar) async -> HealthMetricSeries {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return .empty }
        let startOfToday = calendar.startOfDay(for: now)
        let start = startOfToday.addingTimeInterval(-6 * 3600)
        let end = min(now, startOfToday.addingTimeInterval(12 * 3600))
        guard end > start else { return .empty }
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                guard error == nil, let samples else {
                    continuation.resume(returning: HealthMetricSeries(total: nil, buckets: [], errorMessage: Self.queryErrorMessage(error)))
                    return
                }
                let intervals = samples.compactMap { sample -> DateInterval? in
                    guard let category = sample as? HKCategorySample,
                          let value = HKCategoryValueSleepAnalysis(rawValue: category.value),
                          [.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM].contains(value) else { return nil }
                    let lower = max(category.startDate, start)
                    let upper = min(category.endDate, end)
                    return upper > lower ? DateInterval(start: lower, end: upper) : nil
                }
                guard !intervals.isEmpty else {
                    continuation.resume(returning: .empty)
                    return
                }
                let merged = HealthAccessService.mergeIntervals(intervals)
                let bucketLength = (end.timeIntervalSince(start)) / 12
                let buckets = (0..<12).map { index -> Double in
                    let bucketStart = start.addingTimeInterval(Double(index) * bucketLength)
                    let bucketEnd = bucketStart.addingTimeInterval(bucketLength)
                    let overlap = merged.reduce(0.0) { total, interval in
                        total + max(0, min(interval.end, bucketEnd).timeIntervalSince(max(interval.start, bucketStart)))
                    }
                    return min(1, overlap / bucketLength)
                }
                let hours = merged.reduce(0.0) { $0 + $1.duration } / 3600
                continuation.resume(returning: HealthMetricSeries(total: hours, buckets: buckets))
            }
            store.execute(query)
        }
    }

    nonisolated static func queryErrorMessage(_ error: (any Error)?) -> String? {
        guard let error else { return nil }
        let value = error as NSError
        // Statistics queries can report an empty date range as HKErrorNoData.
        // Empty shared data is not a query failure or proof of denied access.
        if value.domain == HKErrorDomain && value.code == HKError.Code.errorNoData.rawValue { return nil }
        return error.localizedDescription
    }
}

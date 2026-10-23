import Foundation
import HealthKit
import Observation

@MainActor @Observable final class HealthAccessService {
    var isRequesting = false
    var error: String?
    var hasRequested: Bool
    private let store = HKHealthStore()
    private let defaults: UserDefaults
    private let capability: any RuntimeCapabilityProviding
    init(capability: any RuntimeCapabilityProviding, defaults: UserDefaults) {
        self.capability = capability; self.defaults = defaults
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
            try await store.requestAuthorization(toShare: [], read: Self.readTypes)
            // This records only that the system flow completed, never read authorization.
            hasRequested = true; defaults.set(true, forKey: "health.requested")
        } catch { self.error = error.localizedDescription }
    }
}

import Foundation
import HealthKit
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(ImagePlayground)
import ImagePlayground
#endif

enum CapabilityStatus: Equatable, Sendable {
    case available
    case unavailable(Reason)

    enum Reason: Equatable, Sendable {
        case requiresOS(String)
        case deviceNotEligible
        case intelligenceDisabled
        case modelNotReady
        case systemUnavailable
    }

    var isAvailable: Bool { self == .available }
    var explanation: String {
        switch self {
        case .available: "Available on this device"
        case .unavailable(.requiresOS(let version)): "Requires iOS \(version) or later"
        case .unavailable(.deviceNotEligible): "This device does not support the on-device model"
        case .unavailable(.intelligenceDisabled): "Apple Intelligence is not enabled"
        case .unavailable(.modelNotReady): "The on-device model is not ready"
        case .unavailable(.systemUnavailable): "Not available in the current device configuration"
        }
    }
}

struct CapabilitySnapshot: Equatable, Sendable {
    var healthKit: CapabilityStatus
    var foundationModels: CapabilityStatus
    var imagePlayground: CapabilityStatus
}

@MainActor protocol RuntimeCapabilityProviding {
    func currentCapabilities() -> CapabilitySnapshot
}

@MainActor struct SystemCapabilityProvider: RuntimeCapabilityProviding {
    func currentCapabilities() -> CapabilitySnapshot {
        CapabilitySnapshot(
            healthKit: HKHealthStore.isHealthDataAvailable() ? .available : .unavailable(.systemUnavailable),
            foundationModels: foundationModelStatus(),
            imagePlayground: imagePlaygroundStatus()
        )
    }

    private func foundationModelStatus() -> CapabilityStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable(.deviceNotEligible)
                case .appleIntelligenceNotEnabled: return .unavailable(.intelligenceDisabled)
                case .modelNotReady: return .unavailable(.modelNotReady)
                @unknown default: return .unavailable(.systemUnavailable)
                }
            }
        }
        #endif
        return .unavailable(.requiresOS("26"))
    }

    private func imagePlaygroundStatus() -> CapabilityStatus {
        #if canImport(ImagePlayground)
        if #available(iOS 18.2, *) {
            return ImagePlaygroundViewController.isAvailable ? .available : .unavailable(.systemUnavailable)
        }
        #endif
        return .unavailable(.requiresOS("18.2"))
    }
}

// Preview/UI-test injection stays separate from production checks and cannot grant
// permissions or make a device capable of executing an unsupported operation.
struct FixedCapabilityProvider: RuntimeCapabilityProviding {
    let snapshot: CapabilitySnapshot
    func currentCapabilities() -> CapabilitySnapshot { snapshot }
}

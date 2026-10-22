import XCTest
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
}

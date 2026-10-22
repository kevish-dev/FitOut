# Verification log

Tests use standard iPhone 17 / iOS 26.5 in Xcode 27.0. Device-only HealthKit and Apple Intelligence behavior is not verified by simulator results.

## Foundation checkpoints

- Legacy reference onboarding: 8 tests passed.
- SwiftData store: 14 tests passed, including disk reopen, idempotent import and unreadable-store preservation.
- Runtime capabilities: 16 tests passed. No permissions requested.
- Dependency injection and recoverable startup: 16 unit tests passed. Failed completion does not navigate; retry can save.
- Navigation UI test initially failed because SwiftUI combines a LabeledContent accessibility label (“Name, UITest”). All five tab transitions and Settings navigation passed. Corrected assertion checks the combined label.

## Test execution

Run Product > Test in Xcode using the FitOut scheme. Shell builds cannot access CoreSimulator/compiler macro services in this managed environment. `python3 Tools/test_result.py` summarizes the latest completed Xcode xcresult. It does not run tests. Debug-only UI fixtures use a separate in-memory database and unavailable integration providers; production never receives fixtures.

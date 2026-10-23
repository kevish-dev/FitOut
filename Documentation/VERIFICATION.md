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

## Phase 0 complete

Build succeeded; 17 tests passed, 0 failed/skipped/warnings. Five-tab navigation and Settings work with unavailable Health/AI providers. Commit `da36a07`.

## Phase 1 complete

Build succeeded; 23 tests passed, 0 failed/skipped/warnings (Xcode result 05:30:35, 2026-10-23). Includes two UI tests: all-tab navigation and real onboarding completion/relaunch/Settings. Unit coverage verifies optional fields, single-goal validation, height conversions, profile edits, and V1→V2 disk migration.

`Features/Profile` owns the new PRD profile, validation, form and editor. `SchemaV2.UserProfile` stores canonical numeric measurements and nullable optional fields. Drafts save after each change; final completion saves before navigation. Legacy multi-goal records remain intact and require explicit primary-goal selection. All Phase 1 acceptance criteria pass on simulator. No device-only APIs are involved. Next: Phase 2 Home state resolver and setup flows, with interfaces for later routine/nutrition data.

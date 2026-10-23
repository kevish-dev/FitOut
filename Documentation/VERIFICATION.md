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

## Phase 2 Home foundation

Build succeeded; 26 tests passed, 0 failed/skipped/warnings (05:34 test run). Home state tests cover no routine, flexible, scheduled, rest and completion priority. UI tests verify explainer dismissal, relaunch and toolbar Settings. A prior run had two obsolete Settings-selector failures; both pass after using the always-visible toolbar action.

`HomeStateResolver` separates dashboard behavior from views. `HealthAccessService` provides the required optional connection action with read-only HealthKit types; actual readings remain Phase 7. Explainer/request flags persist in isolated preference stores for tests. Production currently has no routine/session input until Phases 3/4, and no nutrition totals until Phase 6; those integration acceptance checks remain explicitly pending. Next: routine builder and catalogue, then connect real Home input.

Apple authorization API evidence: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data — read permission cannot be inferred from a successful request or an empty query. No permission sheet or physical-device HealthKit access has been automatically approved/tested.

## Phase 3 storage checkpoint

Build succeeded; 29 tests passed, 0 failed/skipped/warnings. Commit `00c253e` adds Schema V3 relationships for routines/days/planned exercises and the local exercise catalogue. Tests cover weekday mapping, day swaps, duplication identity, single active routine, CRUD/reload, custom exercise references and invalid load rejection. Home now reads the actual active routine for the local calendar weekday.

Routine editor/library build then passed 30 tests, including UI creation/reopening of a Full Body routine, library navigation, and front/back muscle-map switching. A direct SVG selection assertion is also being run before the phase closes. Illustrations were reused from the workspace's existing `3D-Modal/Design/anatomy-{front,back}.svg`; they are bundled locally with no network dependency. Selected regions expose aria-pressed and a separate selected-muscle text list.

The additional SVG-only button query failed: WebKit exposed the illustration as generic accessibility content rather than queryable buttons. Native named muscle controls now accompany the SVG and share its selection state, with explicit checkmarks/selected traits. The corrected UI test checks selection through those controls. Direct touch regions retain the SVG message bridge. This fixes an accessibility issue rather than suppressing the failed assertion.

## Phase 3 complete

Final run 05:44:01: build succeeded; 30 tests passed, 0 failed/skipped/warnings. Native muscle selection, selected-label feedback, front/back map navigation, routine creation/editing, persistence and schedule logic pass. Routine-driven Home states are now wired; completed-session Home integration remains Phase 4. No AI/HealthKit dependency exists in Gym. Next: autosaved workout execution and independent historical snapshots.

## Phase 4 storage checkpoint

Build succeeded; 33 tests passed, 0 failed/skipped/warnings. Commit `f439044` adds Schema V4 session/entry/set relationships. Disk-reopen tests recover completed sets and pause state, exclude paused time, and preserve workout snapshots after deleting the source routine. Invalid numeric input and duplicate active sessions are rejected; volume excludes warm-up/bodyweight/duration/incomplete sets.

The initial session UI test found that a sheet attached to a List Section did not present even though the session was saved. Presentation now belongs to GymView's root. A Settings toolbar transition after relaunch was also made explicit. Both are under regression verification; Phase 4 is not marked complete until the UI recovery test passes.

## Phase 4 complete

The focused final run passed 31 tests (30 unit tests plus the workout UI test), 0 failed/skipped/warnings. The three other UI workflows passed in the immediately preceding full run. Set completion needed an explicit button style inside its multi-control row; the test now also waits for the saved checkmark before termination. It successfully terminates/relaunches, recovers the completed set, and finishes to the summary. Full-suite selection is restored in the committed scheme.

`WorkoutStore` saves every accepted mutation synchronously and rolls back errors. `WorkoutViews` exposes quick/planned sessions, sets, types, load/reps/duration/distance/RPE, notes, pause/resume, replacements, rest deadlines, and completed/skipped/abandoned history. Home uses actual completion data and starts planned sessions without making View Routine start a workout. Snapshot/duration/recovery acceptance criteria pass on simulator. New-PR indicators and historical charts are Phase 5. Background haptic delivery is not promised; the completion cue is emitted when the visible session observes its elapsed deadline.

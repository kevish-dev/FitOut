# Implementation plan and repository audit

Authoritative requirements: [PRD v1.0](PRD.md). Scope: **all PRD phases**, authorized by the latest “complete this app end to end” request. User requests a Git checkpoint after each small feature. Target device: standard iPhone 17, portrait.

## Existing implementation, 2026-10-23

- Swift 6 / SwiftUI, XcodeGen project, iOS 18 deployment target, no third-party runtime dependencies.
- Installed Xcode 27.0 / iOS 27 SDK; available test destination iPhone 17 running iOS 26.5. Retain stable iOS 18 baseline and gate newer capabilities at runtime; do not raise minimum deployment to the installed beta SDK.
- Five reference-based onboarding screens, avatar import, age/weight controls, local UserDefaults snapshot, completion summary, eight passing XCTest cases.
- Missing Phase 0 deliverables: app-wide navigation/tabs, dependency container, service protocols, SwiftData schema/migrations, runtime capability abstractions.
- Missing all Gym, Nutrition, Health, AI, progress and reminders product modules. These must not be presented as implemented.
- No existing AGENTS.md in the repository or applicable parent workspace. Original repository had no commits; current work is checkpointed before foundation changes.

## Requirement differences reserved for Phase 1

- Existing reference flow allows multiple goals; PRD requires exactly one of six primary goals.
- Existing flow lacks height and treats gender and target weight as required; PRD makes the latter optional.
- Existing completion summary must become Home routing; profile editing must be reachable from Settings.
- Existing draft data must be preserved during changes. Never silently choose a primary goal from a legacy set.
- PRD mentions lime tokens; user explicitly approved the supplied orange theme. Keep centralized orange/charcoal tokens and defer visual refinement.

## Phase 0 checkpoints

1. Versioned local SwiftData store and repository interfaces; preserve existing onboarding through a one-time legacy import; add persistence, rollback, and migration tests.
2. Injected runtime capability provider for HealthKit, on-device Foundation Models, and Image Playground. Availability checks only, no authorization, queries, generation or network traffic.
3. Dependency container, recoverable startup, five-tab navigation and Settings entry. Keep all unfinished modules as honest empty states with working navigation, not fake data or inactive action buttons.
4. Build and run tests on iPhone 17, navigate all tabs with integrations unavailable, test relaunch and record actual results. Report actual results, then continue Phase 1.

## Roadmap after Phase 0

| Phase | Deliverable | Depends on |
|---|---|---|
| 1 | PRD onboarding, one primary goal, full profile, Settings editing, resume | 0 |
| 2 | Real Home states, setup checklist, Health explainer | 1 |
| 3 | Routine CRUD, exercise catalogue, schedule, SVG muscle map | 2 |
| 4 | Workout execution, autosave, recovery, history | 3 |
| 5 | Deterministic volume/PRs/calendar/analytics/export | 4 |
| 6 | Food, recipes, targets, water and totals | 0–2 |
| 7 | HealthKit authorization, queries, normalization, deduplication | 0, 2, 6 |
| 8 | Protected photos, measurements, reminder scheduling | 0–7 |
| 9 | On-device AI chat, deterministic context, validated proposals and confirmation | 0–8 |
| 10 | Full Settings, privacy, export/delete, accessibility, migration/device validation | 0–9 |

## Constraints

- Shell sandbox blocks CoreSimulator and compiler plugin processes. Use Xcode's native UI for builds and simulator tests; read copied xcresult artifacts for test counts. No security settings need to change.
- XCTest baseline: 8 executed, 0 failures, 0 skipped on iPhone 17 / iOS 26.5; build succeeded. Verified in the result bundle, not inferred from compilation.
- HealthKit and AI require later physical-device validation. Capability status is not authorization and must not be advertised as tested health data access.
- Never reset or replace a failed disk store with an in-memory store. Preserve files and expose retry.
- Future schema changes append a new VersionedSchema and migration stage; freeze released schema definitions.

## API evidence

Checked installed SDK interfaces and Apple documentation for:

- [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema) and `SchemaMigrationPlan`; CloudKit explicitly disabled.
- [HealthKit availability](https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()). No read-authorization inference.
- [SystemLanguageModel availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.property), iOS 26+, including not eligible, not enabled and model not ready.
- [ImagePlaygroundViewController.isAvailable](https://developer.apple.com/documentation/imageplayground/imageplaygroundviewcontroller/isavailable), gated at iOS 18.2+. This check does not invoke an image-generation workflow.

No beta-only generation APIs or external AI providers are used.

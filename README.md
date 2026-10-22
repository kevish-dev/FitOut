# FitOut

Native, local-first SwiftUI fitness app for iPhone 17. Swift 6, iOS 18+, no third-party runtime dependencies or backend. On-device Apple Intelligence requires iOS 26 and runtime availability.

Open `FitOut.xcodeproj`, choose the **FitOut** scheme and **iPhone 17**, then Run or Test. With XcodeGen installed, `xcodegen generate` regenerates the project from `project.yml`.

The approved orange/charcoal visual theme lives in `Views/DesignSystem.swift`. Functional implementation follows [the PRD](Documentation/PRD.md) and [phase plan](Documentation/IMPLEMENTATION_PLAN.md). See [actual verification results](Documentation/VERIFICATION.md) for completed checks and limitations.

Data stays on this device in a versioned SwiftData database. Existing onboarding drafts import once from the original UserDefaults format without deleting the backup. Failed stores are preserved and show Retry. HealthKit and Apple-native AI are optional capabilities, never prerequisites for manual tracking.

This repository is under active implementation; unfinished modules display honest empty states. No demo workouts, meals, health readings, or progress statistics are seeded into production data.

# Customizable haptics

Settings → Haptics & vibration contains a master switch, overall intensity,
per-cue controls and previews. Each of 14 cues has an enable switch, intensity
(0–100%), pulse count (1–5), spacing (0.12–0.60 seconds) and Soft/Balanced/Crisp feel.
Overall intensity multiplies cue intensity; zero is silent. Saving or disabling
settings stops any current pattern immediately. A confirmed reset restores default
patterns and turns background rest notifications off.

The app uses Core Haptics transient patterns with no audio. A best-effort UIKit
fallback handles engine failure; physical sensation depends on hardware and iOS.
Unsupported hardware/simulators can save settings but cannot preview vibrations.
The existing SwiftData hapticsEnabled preference remains the master flag. Detailed
versioned settings live in the app's UserDefaults, preserving appearance and other
preferences without a schema change. The old haptics.disabled flag is respected
until an explicit save migrates it. Failed preference saves retain active settings
and show an error.

## Covered events

- Workout start, completed/skipped set, rest expiry, next set/exercise start,
  pause/resume and workout completion use saved session transitions. Repeated
  no-op actions and failed saves cannot duplicate completion cues.
- A rest coordinator lives outside the editor, so an active rest timer still
  advances and signals while a workout is minimized or another FitOut page is open.
  Pausing, extending/skipping rest, ending/deleting a workout or backgrounding
  cancels/replaces obsolete timer tasks. Recovery advances expired timers without
  replaying old cues. Completing the final set uses the completion cue, rather
  than overlapping completion and set cues.
- Selection/navigation feedback covers onboarding pickers, avatar/goal choices,
  height/weight/age commits, exercise selection, navigation menu/tab changes and
  shared Next/Back controls. Save/log feedback follows persisted routines, exercise
  changes, food/recipe/meal/target changes, hydration changes and profile completion.
  Coach send/record-summary actions, completed replies and streak celebrations
  share the configurable service.
- Draft autosaves, typing, streaming tokens, chart/widget cache refreshes, app
  startup and countdown ticks stay silent. Rapid selection repeats are limited;
  low-priority selection/save/chat feedback cannot interrupt a rest or completion
  pattern. All previous direct app feedback generators route through this service.

## Background/locked-screen rest alerts

This option defaults off. Enabling it from Settings requests notification access;
building, launching or starting a workout never requests it automatically. One
stable notification identifier is replaced when a rest deadline changes and
removed on pause, rest skip, finish, deletion, master off, zero overall intensity
or a disabled/silent rest cue. Replacement operations serialize so an older async
add cannot win over cancellation. Notification taps open the existing active
workout route, including cold launch. Foreground notification presentation is
suppressed in favor of the single custom haptic cue.

iOS suspends custom Core Haptics in the background. Background/locked-screen
alerts therefore use the system notification sound and vibration settings;
FitOut cannot control their vibration strength/count or guarantee delivery under
Focus, Silent Mode or user notification preferences. A Live Activity countdown
does not itself guarantee a vibration. No keepalive/background-mode workaround
or external dependency was added.

Settings explain these limits and expose denied authorization without implying
that an alert is guaranteed. Existing water reminder behavior is retained.
Native iOS pickers/controls and system notifications may produce their own
feedback outside FitOut's generated cues.

## Validation

Unit coverage verifies pattern parameters, bounds, global/per-cue silence,
legacy preference migration, save rollback, foreground-only output, priority and
deduplication, real rest expiry with no editor, pause/extend/off notification
replacement, permission denial, background recovery and no permission prompt on
ordinary workout use. Physical-iPhone validation remains necessary for sensation,
engine interruptions, notification delivery and locked-screen behavior.

Checkpoint: the full 243-test suite passed with zero failures, including 12
haptic tests. The unsigned iPhone app/widget/test build passed. An unrelated
coach timeout test initially raced its fixed 50 ms wait under simulator load;
it now waits for the observable timeout state within a bounded deadline.
No interactive app/device UI or real haptic sensation was automatically tested.

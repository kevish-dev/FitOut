# Ongoing workouts and Live Activities

The [focused workout state machine](FOCUSED_WORKOUT.md) owns ready, active-set,
rest, pause, exercise-transition and completion behavior. UI and Live Activity
actions use the same persisted session. Laps were removed from the UI and action
allowlist; old optional history payloads remain decodable and exportable.

A single draggable glass control keeps an active workout reachable over app
navigation and sheets. It displays running/paused status, active workout time,
pause/resume and tap-to-open. It respects the saved appearance, moves above the
keyboard and hides while a workout editor is visible. Ending the workout removes
it; Undo can restore the active workout.

ActivityKit compact/minimal layouts show status and elapsed workout time.
Expanded and Lock Screen layouts add exercise, current set/total sets, inputs,
completed/skipped counts, active-set timing and rest countdown. Quick actions
pause/resume, start a ready set, extend rest by 15 seconds or skip rest. Recording
actual completed sets remains an explicit action in the app. No lap action is
exposed. Session IDs, revision checks and receipts reject stale or duplicate
commands; the extension never writes SwiftData files directly.

Clocks use saved timestamps and system-rendered timer text, without continual
background sampling, a network service or push entitlement. Activity updates are
serialized and bounded. The coordinator distinguishes app-ended activities from
user dismissal so Undo can restore an activity without overriding a person's
explicit dismissal. Workout Options → Show Live Activity allows an explicit retry.

Device support, user settings and iOS determine visibility. Apple limits a Live
Activity to eight hours; persisted session tracking continues beyond that limit.

References: [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities),
[interactive Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

Simulator unit tests cover execution, interruption recovery, stale commands and
projection. Generic-iOS unsigned build-for-testing checks the app and extension.
Physical-device Dynamic Island, Lock Screen interaction and visual checks remain
necessary; no interactive UI automation is performed as part of this change.

# Ongoing workouts

One persisted `WorkoutSession` drives the workout editor, the app-wide floating
control, widgets, and ActivityKit. Quick and planned workouts use the same path.

## Recording

- Active duration is derived from timestamps and accumulated pause time. Closing
  the editor, backgrounding, and reopening FitOut do not reset the clock. Paused
  sessions remain paused until explicitly resumed. Total elapsed and paused time
  are available separately in Timing & laps.
- Every pause interval and explicit lap is saved. Laps contain wall duration,
  active duration, cumulative active duration, start/end timestamps and the
  focused exercise identifier. Paused time is excluded from active lap splits.
- Each set can have an optional timer. Start it explicitly; pause/resume of the
  workout also freezes/resumes its active clock. Stop keeps the measured duration;
  starting another set freezes the previous timer without logging it. A manual
  restart begins a fresh measurement and preserves the earlier action in the
  timeline. Logging a duration exercise with a running timer uses measured seconds.
  Logging without a timer uses the manually entered duration. Undo resets timer
  anchors and keeps the old logged values in the event evidence.
  Skipping an exercise or ending the workout freezes any unlogged set timer
  without marking that set completed.
- Completed timestamps, active-time offsets, measured set durations, reps, load,
  distance, set type, RPE and prescription targets persist. Events retain before/
  after values for logging, corrections, undo and deletion. Exercise changes,
  notes, rest deadlines, pause/resume, laps and finish are also recorded. Consecutive
  typing edits within two seconds coalesce; explicit actions do not.
- The optional JSON supplement extends the existing V5 session-details record.
  Historical SwiftData schemas are untouched. Older sessions decode without
  telemetry. An already running legacy session starts detailed recording when
  loaded; its original totals are kept and the coverage start is disclosed.
- Timing & laps is available during the workout and from its saved summary. Full
  session JSON export includes millisecond timestamps and the event history.

## Floating access

A single glass control shows running/paused status, active time, pause/resume and
tap-to-open. Drag it to either edge and vertically to keep other controls usable.
A pass-through scene window lets it remain above navigation and sheets while
allowing taps through everywhere outside its bounds. It moves above the keyboard
and hides while a workout editor is already visible. The editor provides set,
lap, notes and finish actions. The control disappears when the workout ends.

## Dynamic Island and Lock Screen

- Live Activities start for an active workout when FitOut is foregrounded and
  system authorization permits. Compact/minimal Island layouts prioritize the
  status and elapsed clock. Expanded and Lock Screen layouts add the focused
  exercise, sets, laps, current set timer or last lap, and rest countdown. The Lock
  Screen also shows the most recently logged set.
- Pause/resume, record lap and end-rest use `LiveActivityIntent`. The system runs
  those intents in the containing app process. A shared main-actor app container
  uses the same SwiftData store as the UI; the extension never writes workout DB
  files. Successful mutations are persisted before updated activity content is
  published. Session-ID guards reject ended sessions. Revision/action receipts
  suppress repeated delivery of the same displayed command across reloads.
- System-rendered clocks use saved anchors. No continuously running background
  timer, network service, push entitlement or sensor sampling is required. Rest
  uses a stale date; expired rest is reconciled on the next action or foreground.
  Activity updates are serialized and contain a bounded projection, not the full
  event history. Ended/deleted workouts end their activity immediately.
- User dismissal is respected. The workout continues recording; the editor offers
  an explicit Show Live Activity action. Disabled/unavailable activities do not
  prevent using the app or floating control. Device support and iOS determine
  presentation and whether the Island is currently visible. Apple limits a Live
  Activity to eight hours; persisted workout timing continues beyond that limit.

References: [Apple ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities),
[interactive Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

## Verification

Regression sources cover pause/lap arithmetic across store reload, finish while
paused, explicit set timers, duration logging, undo/deletion evidence, typing edit
coalescing, old JSON decoding, legacy coverage, duplicate/stale activity actions,
clock projection and a bounded ActivityKit payload. Generic-iOS unsigned
`build-for-testing` compiles the app, widget extension and test targets. No tests,
app, simulator or device are launched by this change.

On-device verification remains necessary for Dynamic Island expansion, locked-
screen actions after process termination, dismissal/disabled settings, keyboard
placement and dragging the floating control across modal screens. Timing logic
has build-checked regression coverage; those tests have not been executed.

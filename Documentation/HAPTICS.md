# Customizable haptics

Settings → Haptics & vibration contains a master switch, overall intensity,
per-cue controls and previews. Each of 14 cues has an enable switch, intensity
(0–100%), pulse count (1–10), pulse length (0–0.80 seconds), gap between pulses
(0.12–1.00 seconds) and Soft/Balanced/Crisp feel. Zero length is a transient tap;
positive length uses sustained Core Haptics events. Gaps follow each event's end,
so long pulses never overlap. Maximum custom pattern length is 17 seconds.
Overall intensity multiplies cue intensity; zero is silent. Saving or disabling
settings stops any current pattern immediately. A confirmed reset restores default
patterns and turns background rest alerts off. Use strong workout vibrations
restores strong workout/streak cues and full overall intensity, leaving unrelated
custom cues, the master switch and background permission preferences alone.

New defaults use full overall intensity. Rest expiry is five full-intensity
0.45-second bursts separated by 0.25-second gaps (3.25 seconds total). Other
workout cues use shorter sustained bursts; picker/navigation cues remain brief.
The app uses Core Haptics transient/continuous patterns without audio. A heavy
UIKit impact fallback handles engine failure, without promising continuous
vibration on unsupported hardware. Physical sensation depends on hardware/iOS;
Core Haptics intensity cannot exceed the platform maximum or promise exact parity
with an incoming call. Priority suppression includes the final burst's duration,
so lower-priority UI feedback cannot cut the rest alert's tail short.
Unsupported hardware/simulators can save settings but cannot preview vibrations.
The existing SwiftData hapticsEnabled preference remains the master flag. Detailed
versioned settings live in the app's UserDefaults, preserving appearance and other
preferences without a schema change. The old haptics.disabled flag is respected
until an explicit save migrates it. V1 settings decode into V2, preserving custom
intensity, cue settings and existing notification opt-ins. Missing pulse length
in a saved cue retains its old transient behavior. Existing notification users
are never silently switched to alarm access. Failed preference saves retain
active settings and show an error.

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

Background rest alerts default off. Settings offers Notification or, on iOS 26+,
System alarm. The new-install preference is System alarm; older OS versions
resolve to Notification. Selecting a type while alerts are off never requests
access. Enabling alerts, or changing an enabled alert type, requests the chosen
system permission. Denial leaves the previous settings intact. Building,
launching and ordinary workout actions never request access automatically.

System alarm uses AlarmKit with a single stable UUID and fixed rest deadline.
The alarm is scheduled when FitOut becomes inactive/backgrounded; foreground
uses the custom sustained vibration. Opening FitOut cancels its alarm, so there
are no simultaneous native/custom rest cues. AlarmKit owns locked-screen alerting,
sound, system vibration and dismissal, with an Open workout action that routes
to the active session. The permission description is in the app Info.plist.
There is no second alarm countdown Live Activity; the existing workout countdown
continues to show rest. AlarmKit can alert through Silent mode/Focus, and can
make sound; there is no custom or vibration-only alarm-pattern promise.

Notification keeps the existing stable local notification identifier and standard
system sound. Notification taps open the active workout, including cold launch;
foreground notification presentation is suppressed. Notification vibration and
delivery depend on the person's iOS sound, haptic, notification and Focus settings.

Both channels are cancelled/replaced on pause, resume, rest extension/skip,
finish/deletion, master off, zero intensity or a disabled/silent rest cue. Only
one channel is scheduled; switching clears the other. Cancellation attempts both
channels even if one fails. Async replacements serialize so an older schedule
cannot win over a newer cancellation. Locked-screen Live Activity actions await
the alert update before returning. A stable alarm UUID allows cleanup after
relaunch without touching unrelated alarms. Scheduling checks authorization and
never prompts implicitly. No keepalive/background audio mode or dependency is added.

iOS suspends custom Core Haptics in the background. AlarmKit is the supported
system alternative on iOS 26+, but does not expose custom vibration strength,
length or repetition controls. A Live Activity countdown alone does not vibrate.

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

Checkpoint: the full 285-test suite passed with zero failures, including 20
haptic tests. Coverage includes sustained event lengths/gaps/bounds, final-burst
priority, legacy decoding, persisted custom duration, native alarm mode selection,
foreground/background switching, unsupported-OS fallback, permission denial,
one-channel routing and cancellation failures. The unsigned iPhone app/widget/test
build passed. Physical intensity, actual AlarmKit permission prompts, ringing,
Lock Screen delivery and engine interruptions require iPhone validation by the
owner. No interactive app/device UI or physical haptic sensation was tested.

Platform references: [Apple's AlarmKit overview](https://developer.apple.com/videos/play/wwdc2025/230/)
and [Core Haptics engine lifecycle](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics).

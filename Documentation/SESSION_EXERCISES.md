# Active session exercises and number wheels

Quick and planned sessions share Session exercises, reachable directly above the
current exercise or through Workout options. A native List shows exercise artwork,
remaining/logged counts, current status, action menus and native drag handles.
Drag any exercise to another position; Move to first is available as a menu
alternative. Do this next explicitly switches focus and dismisses the manager.
Changes save immediately to this session and do not edit the saved weekly routine.

## Queue and record rules

- Reordering before an unstarted set follows the new queue. Reordering during an
  active set preserves its focus, inputs and running timer. Reordering during rest
  preserves the rest deadline and changes the order used after rest ends.
- Do this next confirms ending rest and stopping the current set timer. It leaves
  the interrupted set pending with its elapsed time frozen, moves the selected
  exercise to the front, and waits for Start set/Start exercise. Returning to an
  interrupted set accumulates its previous active time while excluding time spent
  on other exercises. A paused workout stays paused after switching.
- Skip exercise confirms marking every remaining set skipped, with no fabricated
  actuals/volume. Completed sets remain untouched. Skipping a future exercise does
  not stop the current running timer. Current exercise skip advances safely.
- Remove deletes only unlogged work. If records exist, the action is named Remove
  remaining sets, and the recorded portion remains visible. Removing all remaining
  work never silently completes the session; Finish remains explicit.
- Replace chooses an alternative from the existing exercise library and asks for
  confirmation. Remaining set count/types/rest are reused; previous weight/reps
  come from the replacement exercise's own history. New duration movements get
  30-second targets when no history exists; duration-to-rep replacements default
  to 8 reps. Old exercise loads are not copied to a different movement.
- If a replaced exercise already has records, its recorded snapshot stays in the
  session and a new entry holds the replacement's fresh set IDs. Otherwise its
  entry slot is reused with fresh sets. Replacing the current exercise ends rest
  and waits for an explicit start. These changes never rewrite historical actuals.
- Structural removal/skip/replacement clears incompatible set-level Undo. Simple
  focus/reorder preserves applicable Undo. Confirmation protects destructive and
  timer-changing actions. Stale session IDs and reorder lists fail safely.
- The existing atomic workout save path, supplementary JSON and telemetry capture
  queue edits and focus changes. No SwiftData schema or backend is added. Live
  Activity, floating control, rest/haptic coordinator and summaries read the same
  persisted session. Add-exercise setup is bound to the session that opened it.

## Weight and reps

The active set and quick/setup set editors now use vertical snapping number wheels
styled like onboarding's age picker: a highlighted center row, faded neighbors
and orange side marks. Reps move by 1; weight moves by 0.5 kg or 1 lb. Enter exact
opens a native numeric sheet for fractional increments and direct entry, validating
the value before Save. Unit changes only convert display values; canonical data
remains kilograms. Recalled off-grid weights are retained until deliberately
changed; loading a wheel does not round and save them.

The LazyVStack virtualizes rows. A wheel saves when scrolling settles, not on every
deceleration frame. Completion/Done is disabled while a wheel or exact entry is
active, so logging cannot race an old value. Picker identity follows set/unit,
and late callbacks cannot write to a different current set. VoiceOver adjustable
actions, exact entry and Dynamic Type support alternatives to dragging. Haptic
selection feedback obeys the shared settings. Duration/distance and optional
effort/rest controls retain their existing inputs.

## Verification

Unit tests cover reordering ready/active/resting sessions, switching and resuming
timed work, paused switching, skip/remove/replace with historical actuals,
replacement-specific recall, stale operations, disk reopen and saved-routine
isolation, wheel bounds/fractions and blocked logging during input. The owner
still needs to check native drag behavior, nested scroll feel, compact/large-text
layouts and physical haptics on iPhone. No interactive simulator/device UI was used.

Checkpoint: all 264 unit tests passed with zero failures, including 14 new session
editing/input regressions. The unsigned iPhone app/widget/test build passed. A
test-fixture initializer order was corrected before the passing runs; no device
gesture or visual verification is claimed.

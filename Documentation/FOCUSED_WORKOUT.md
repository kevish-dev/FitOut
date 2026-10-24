# Focused active workout

Quick workouts and saved routines open the same native SwiftUI screen. Ordered
exercise definitions and planned sets are copied into a session; routine edits
cannot rewrite it. Quick workouts first use the [configuration flow](QUICK_WORKOUT_SETUP.md): users
select and configure every exercise before Start creates a session. Later additions
use the same configure-first editor and extend that snapshot without starting a set.

## Interface

The compact header shows workout type/name, minimize, labelled total workout time
and options. Progress shows exercise and set position. One exercise illustration
is prominent, with equipment and primary/secondary muscles. Technique uses the
saved exercise definition and supplied image. Images are fitted and zoomable;
missing artwork is disclosed rather than replaced with a different exercise.

The exercise stage follows the reference's hierarchy: fitted exercise artwork,
a floating native glass pause/resume capsule, and a large semicircular timer with
an orange status marker. The image stays zoomable; missing artwork has an explicit
fallback. Stage proportions adapt to available height; larger Dynamic Type allows
scrolling instead of cropping text or hiding controls. Equipment and primary
muscles stay beside the exercise name; the information button opens primary and
secondary muscles, equipment and technique.

The clock switches between Set time and Rest remaining, with explicit paused and
ready labels. For timed exercises, the arc shows elapsed time against the editable
target and caps at 100%; passing the target never completes a set automatically.
Rep-based sets use actual workout set progress because they have no prescribed
time limit. Completed and skipped counts remain distinct. Rest progress includes
extensions and excludes paused time. A shared angular path keeps the marker on the
arc as the view compresses or animates. Reduce Motion disables interpolation.

The compact row under the stage shows sets logged, valid training volume in the
selected unit, and total workout time. These come from the persisted session;
there are no sample heart-rate, calorie or step readings. Editable weight, kg/lb
units and reps remain below, using previous performance recall, numeric inputs and
+/- controls. Duration exercises have a target and optional distance; actual time
comes from the running timer. Validation prevents bad typed values from silently
completing a set with saved defaults. Effort/rest use a disclosure; applying inputs
to remaining sets is explicit. Skip Set, Add Note and Undo remain available.

The safe-area bottom dock previews the next set/exercise beside a circular orange
action. Its visible title explicitly describes Start set, Complete Set, Skip Rest,
Resume workout, Start next exercise or Close summary. It never jumps exercises or
logs a set merely by previewing it. Rest also offers +15s. The dock stays above the
keyboard, with scrollable inputs above it. Options retain add exercises/sets,
set type, timing/history, Live Activity retry, finish early and confirmed discard.
Minimize never ends the session. The existing summary retains all recorded details.

The interface reuses the app's subdued exercise illustrations, theme colors and
fonts, appearance preference, Reduce Transparency and optional haptics. No new
photo assets, dependencies or persistence schema changes are needed.

## State and persistence

`WorkoutExecutionEngine` is a pure explicit state machine: ready, activeSet,
resting, paused, exerciseTransition and workoutCompleted. `FocusedWorkoutModel`
is observable and owns screen transitions, validation and the cancellable rest
deadline task. State, cursor, unit preference, last Undo, set skips, input targets,
actual records and notes persist in the existing V5 JSON supplement. Historical
SwiftData schemas are unchanged. Old sessions normalize into the focused flow.

Start snapshots current inputs and starts the set clock. Complete validates and
saves actual load/reps/measured duration immediately. If work remains, configured
rest begins; expiry/skip advances to the next set or an exercise transition.
The last resolved set ends automatically. Skip stores skippedAt, no completedAt
and no actual record; it never enters completed volume. All-skipped sessions end
as skipped. Finish early keeps unlogged sets unfinished; discard deletes only
after confirmation.

Stable set IDs, expected-current-set guards and resolved statuses make duplicate
completion/skip deliveries no-ops. Live Activity rest/start actions also check
revision and receipts. Saved current state is the authority across minimize,
backgrounding and relaunch. Clocks derive from timestamps and accumulated pause
time. A ContinuousClock foreground anchor avoids tick-count or wall-clock drift;
foreground recovery reanchors to saved timestamps. Pause freezes set and rest
timing; resume shifts rest deadlines. Obsolete deadline tasks cancel on state,
deadline, visibility or scene changes. No per-second database writes occur.

One persisted Undo restores a completed/skipped set to ready, clears its timer
and actual record, and retains inputs. Rewinding stops a later running set timer.
Undo after automatic finish reopens the same session and excludes the closed gap
from workout time. It cannot replace another active workout. History summaries
offer the last-set Undo; the restored session becomes available via the floating
control. Legacy lap payloads are retained only for decoding/export, with no new
lap action or UI.

## Validation

The unit suite includes ordered transitions, rest extension/expiry/skip,
duplicate/stale actions, pause/resume, measured vs planned data, skip volume,
all-skipped completion, Undo before/after finish, later timer cancellation,
on-disk restoration, invalid/empty data, routine snapshot isolation, Live Activity
projection and obsolete-task cancellation. Unit tests run in an iOS simulator.
Unsigned generic-iOS build-for-testing compiles app, extension and test targets.
The arc-screen baseline passed all 167 unit tests with zero failures, including
20 focused-workout tests. Quick-workout setup adds a dedicated regression suite. Stage regressions cover target-time vs rep-based arcs,
rest extensions, frozen paused clocks, skipped-set labels and next-action previews
through the final summary, alongside existing analytics and persistence suites.
UI-test source is updated for the focused recovery flow, but interactive UI tests
are not run. Device visual, gesture, keyboard and Dynamic Island checks remain
with the project owner.

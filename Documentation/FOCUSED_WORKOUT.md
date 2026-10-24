# Focused active workout

Quick workouts and saved routines open the same native SwiftUI screen. Ordered
exercise definitions and planned sets are copied into a session; routine edits
cannot rewrite it. Quick workouts add selected exercises to that same snapshot.

## Interface

The compact header shows workout type/name, minimize, labelled total workout time
and options. Progress shows exercise and set position. One exercise illustration
is prominent, with equipment and primary/secondary muscles. Technique uses the
saved exercise definition and supplied image. Images are fitted and zoomable;
missing artwork is disclosed rather than replaced with a different exercise.

The large labelled clock switches between Active set duration and Rest countdown;
workout time remains separate in the header. Editable weight, kg/lb units and reps
use previous performance recall, numeric inputs and +/- controls. Duration
exercises have a target and optional distance; actual duration comes from the
running timer. Inputs and validation errors are independent so invalid typed
values cannot silently complete a set with old saved defaults. Effort and rest
remain under a disclosure. Apply to remaining sets is explicit and does not edit
the saved routine. Skip Set and Add Note are native actions; notes attach to the
set whose identity was captured when the sheet opened.

The safe-area bottom action is Start set, Complete Set, Skip Rest, Resume workout,
Start next exercise or Close summary according to state. Rest also offers +15s.
Options include pause/resume, add exercises/sets, set type, timing/history,
Live Activity retry, finish early and confirmed discard. Minimize never ends the
session. Summary includes completed/skipped/unfinished counts, actual duration,
valid volume and recorded set details; skipped sets have text and an icon.

The references inform the image-led hierarchy and clear timer/action placement.
Their sample calorie/heart-rate/step readings, copyrighted character art, bright
lighting and unrelated controls are not copied. Existing subdued assets, fonts,
theme choice, Reduce Motion, Reduce Transparency and optional haptics are used.

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
The final simulator run passed all 155 unit tests with zero failures, including
15 focused-workout tests and the existing workout, analytics and persistence suites.
UI-test source is updated for the focused recovery flow, but interactive UI tests
are not run. Device visual, gesture, keyboard and Dynamic Island checks remain
with the project owner.

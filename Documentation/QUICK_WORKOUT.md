# Quick Workout

Gym has an illustrated Quick Workout / Continue session card. Home and Gym share
a photo-led, routine-aware workout preview; an open day can still start a quick session.
The active workout is stored immediately, and closing the sheet keeps it available
for resuming.

## Interaction

- The session header shows real active time, exercise count, logged sets and
  weighted volume where applicable. A progress ring counts logged sets plus
  remaining unskipped targets; it does not count skipped, unlogged sets as a goal.
- The empty state leads to the shared multi-exercise browser. Exercises are added
  in selection order in one store transaction. The first newly added movement
  opens for logging; only one exercise card expands at a time.
- Exercise cards use the supplied system artwork and retain full-screen image
  references. Logging has compact reps/load or duration/distance fields and an
  accessible completion/undo button. Narrow layouts and large text sizes stack
  inputs. Set type, delete and optional effort remain available; session and
  exercise notes use progressive disclosure.
- Add set copies the previous performed inputs into a new working set. It does
  not copy completion, recorded effort, prescription targets or a per-set rest
  override. Logging remains an explicit user action.
- The rest countdown stays in the bottom dock. Pause freezes both active time and
  remaining rest; resume shifts an unexpired deadline by the paused interval.
  Expired rest is not revived. Deadline and pause state persist using existing
  fields. Ending rest, undoing the latest set, or deleting the latest logged set
  removes that countdown. Per-set rest overrides still take precedence.
- The keyboard gets a dedicated Done editing action in the same dock. Completing,
  pausing, replacing, expanding another card and finishing dismiss editing first.
- Finish keeps complete/skipped/abandoned choices. Completion requires a logged
  set. The visual summary shows actual totals, logged set values, existing personal
  record calculations and saved notes. Previously logged sets remain visible even
  when their exercise was later skipped.

## Visuals and performance

The existing `RoutineEquipment` graphic and exercise illustrations are reused;
no new generated asset or remote imagery is required. Cards use the shared Inter/
Orbitron typography, 20 pt page insets, restrained orange and glass treatment.
Timers update local timeline views rather than rebuilding all set editors every
second. The rest ring interpolates between ticks; completion, expansion and dock
changes use short transitions. Reduced Motion and Reduce Transparency settings
are respected. Logging and rest haptics follow the existing disabled preference.

## Verification

Regression-test source covers ordered batch addition, a single change publication,
rest pause/resume across store reload, expired-rest handling, fresh working sets,
and progress with skipped exercises. The existing workout UI test uses the shared
multi-picker. Unsigned generic-iOS `build-for-testing` compiles the app, widgets
and test targets. The app and tests are not run; on-device interaction and visual
verification remain with the project owner.

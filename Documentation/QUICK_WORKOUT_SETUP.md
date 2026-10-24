# Quick workout setup

Home, Gym and the workout sheet now route new quick workouts through a setup
buffer. Selecting exercises, browsing the library, changing targets, and leaving
setup never creates a WorkoutSession, set timer, Live Activity or training volume.
Start workout validates the entire configuration, creates its ordered snapshot,
and starts the first set in one persistence operation. Setup time is excluded.
Existing planned-routine starts and active-session recovery retain their flow.

The overview uses the app's existing exercise images, fonts, semantic surfaces,
20 pt page inset, 16 pt content padding, and native interactive glass for actions.
Users select several exercises together, reorder or remove movements, rename the
workout, choose kg/lb and open each exercise's set editor. A fixed safe-area Start
action stays disabled until every exercise has valid sets. Empty setup explains
the next action. The setup persists separately in the container's UserDefaults,
restores on reopening/relaunch, and clears only after successful start or confirmed
Reset. Cancel in an exercise editor discards that local edit buffer.

Exercises default to three working sets when there is no recorded history, or the
last session's recorded working-set count when available. The existing recall
policy seeds each set's reps, weight, duration, distance and rest by exercise,
tracking kind, set type and ordinal. Warm-ups do not fill working sets. Skipped,
unlogged and invalid values do not become performance defaults. Missing history
uses editable targets rather than a fabricated previous reading. The picker,
overview and individual set rows show recorded performance when available.

Each set editor has direct set-count minus/plus controls, removable future sets,
editable weight/reps or timed targets/distance, per-set type, and rest. Apply to
remaining sets is explicit. Added sets inherit the most recent working inputs.
Typed values use finite/range/integer validation, support the current decimal
separator, and block Done while invalid. Inputs remain canonical kg internally.
All targets confirmed at Start/Add are protected from later automatic recall;
per-set historical differences and explicit edits remain distinct.

During a workout, Manage sets edits the current exercise, and Workout options →
Edit workout plan exposes every upcoming exercise. Add exercises opens the same
configure-first flow; choosing a library row never starts an exercise or changes
the current timer. Editing merges only input fields into the latest session,
preserving started timestamps, actual performance and completed/skipped records.
The current, started, and recorded sets cannot be deleted. New sets remain
unstarted. Stale edits reject changed set lists or a newly resolved set instead of
overwriting live progress. Rest changes apply to pending sets; recorded rest and
an already-running rest deadline stay intact. No schema change or backend is added.

Unit regressions cover draft restoration without session creation, valid explicit
start and recovery, repeated start rejection, invalid/duplicate setup, ordinal
history recall, protected future targets, configured additions, active timer
preservation, completed-record protection, stale edits, rest defaults, input parsing
and ordered exercises. UI-test source covers setup and start before recovery; it
is compiled without running interactive UI automation. Device checks for touch,
keyboard and visual layout remain with the project owner.

Validation: all 181 simulator unit tests passed, including 14 configuration tests.
The unsigned generic-iOS build-for-testing passed for the app, widgets and test
targets. Source review checked setup/start routing, Dynamic Type layout branches,
44 pt controls, safe-area actions and keyboard dismissal; rendered device review
was not performed, consistent with the requested local-build workflow.

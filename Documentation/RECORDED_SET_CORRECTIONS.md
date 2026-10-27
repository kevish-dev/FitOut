# Recorded set corrections and restart

The former Undo action is replaced with Edit last set and Restart last set, in the
active-workout dock and workout summaries. A short label identifies the exercise,
set number and skipped status. Edit is a draft sheet; Cancel saves nothing.
Weight/reps use the shared draggable number wheels with exact entry and kg/lb
conversion. Duration/distance, set type, effort and note can also be corrected.

Correction modifies only editable fields on the original set and its actual
performance. Weight/reps edits do not change measured duration; a duration edit
corrects the recorded seconds without rewriting the underlying clock. Status,
IDs, completion/skip timestamps, planned/input targets and timer anchors stay
unchanged. Pending sets, current exercise and rest are untouched. Corrections
record a setEdited event, refresh volume/records/recall/widgets and do not award
another completion or streak. Legacy sets with no actual payload retain that
format. Skipped records stay skipped with no actual/volume.

Restart uses explicit confirmation before clearing the last result and starting
the same set again. Latest corrected inputs are retained. Restarting while paused
leaves the session paused; restarting a finished workout excludes the closed gap
from elapsed workout time. Another active workout prevents historical restart.
An exact original-record comparison rejects stale edits and repeated restart
requests without overwriting the newer record. All saves use existing local
persistence and the supplementary session JSON; no schema/backend is added.

Verification: all 277 unit tests passed with zero failures, including 13 new
regressions for corrections during rest/active work, clock/target preservation,
status/volume/actual consistency, validation, stale actions, disk reopen, editing
history alongside another workout, streak neutrality, explicit restart and paused
restart. The unsigned iPhone build compiles app, extension and test targets.
The owner should check sheet layout, number-wheel feel and restart confirmation
on iPhone; no interactive app or UI tests were run for this change.

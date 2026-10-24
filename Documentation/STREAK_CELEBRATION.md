# Workout streak celebration

Streak credit uses completed workout records and their finish date. A newly earned
local calendar day triggers the reference-inspired celebration: subdued athlete
photography, orange flame, a counting streak number, seven real weekly checks and
Continue. Today's check springs into place; previous checks remain visible. The
Home streak number also animates when it changes. No sample counts are displayed.

Completing the last set of a quick or planned workout saves the finished session
and can award the day. Finish workout also awards it when the session has recorded
sets and is saved as completed. Starting a workout, creating a routine/setup,
logging a set while the session remains active, skipped/all-skipped sessions and
abandoned sessions do not earn credit. Two completed workouts on one day still
earn just one day. The existing daily-streak rules retain yesterday's streak until
today is missed; gaps restart at one. Midnight crossings credit the finish day;
calendar-day arithmetic handles daylight saving. Malformed finish dates before
start and future finishes are excluded. Legacy completed records without a finish
date retain the existing start-date fallback.

WorkoutStreakStore derives all counts from workout history. Its separate local
UserDefaults ledger tracks only pending and acknowledged celebration days. Existing
history establishes a baseline and does not flood the user with old celebrations.
An earned celebration survives a relaunch until Continue/Close acknowledges it.
Acknowledged days never replay on refresh, a second same-day workout, or same-day
Undo/recompletion. Unacknowledged pending events cancel if their completed-day
credit is undone/deleted; another completion on that day keeps its credit valid.
Pending celebrations expire when their local day ends. Deleting workouts always
recalculates the actual streak, independently of this presentation ledger.

The presenter uses the existing app window and presents a native full-screen cover
above the current workout summary after confirmation transitions settle. Continue
returns to that summary, preserving Undo. If another alert blocks presentation,
the bounded presentation attempt leaves the award pending for the next foreground
refresh. No overlay window or continual animation/timer is added. Test/in-memory
containers disable UIKit presentation while exercising all award logic.

The screen uses existing FitnessHero artwork, FitOut fonts, semantic theme colors,
20 pt page margins and 16 pt internal spacing. Scrolling and a safe-area Continue
button support compact screens and large Dynamic Type. VoiceOver announces the
actual count and each day's recorded status; Close and escape are available.
Reduce Motion shows the final count/checks without motion. Success haptics follow
the saved haptics preference. Existing light/dark/System appearance is respected.

Regression coverage includes initial-history suppression, no award for drafts or
active sessions, automatic completion, explicit Finish after a recorded set,
unique-day credit, consecutive days/gaps, pending recovery and acknowledgement,
Undo/deletion, future/invalid records, midnight and daylight saving. Unit tests and
unsigned iPhone build-for-testing validate the implementation. Interactive device
animation and visual checks are left to the project owner.

Validation results: the full 193-test suite passed with zero failures. After adding
the explicit partial-workout Finish regression, all 13 streak tests passed again.
The final unsigned iPhone build-for-testing passed. No interactive app/simulator
UI was used to verify the animation; physical-device visual checks remain open.

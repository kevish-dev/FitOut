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
earn just one day. Planned rest days preserve the existing count without adding
a completed workout day. For example, two workout days followed by two scheduled
rest days still show 2; the next completed workout shows 3. Today remains available
to train; a past missed non-rest day breaks the chain. Flexible/unassigned days
are not automatically rest days. A completed workout on a rest day still earns
one normal credit. Rest alone never starts a streak or triggers a celebration.
Midnight crossings credit the finish day;
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

Rest protection comes from the active saved routine, not unsaved editor drafts or
inactive/archived routines. A separate effective-dated schedule history in
`fitout.streak.restSchedules.v1` preserves past rest rules when a plan is edited,
switched, archived or deleted. Changes apply from the current local day, so marking
a weekday as rest today does not excuse a missed training day earlier in the week.
On the first upgrade, the existing saved plan supplies the baseline from its
creation/start date; prior schedule versions were not stored and cannot be
reconstructed. Future-start plans do not protect earlier dates. Repeated saves
without rest-rule changes do not create versions; repeated edits today replace
today's version. These snapshots survive relaunch without a SwiftData migration.

Home, celebrations and WidgetKit share the same calendar-day counting policy.
The widget cache carries optional rest-schedule history so old caches still decode.
Moon icons and VoiceOver labels distinguish planned rest from completed checks;
weekly workout-day totals count completions only. This does not change the separate
weekly consistency metric (at least one completed workout in a calendar week).

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
unsigned iPhone build-for-testing validate the implementation. Rest-day regressions
also cover consecutive rest days, no-data/all-rest behavior, the next workout's
award, routine start dates and later edits, relaunch, Undo, DST and widget parity.
Interactive device
animation and visual checks are left to the project owner.

Validation results: the full 193-test suite passed with zero failures. After adding
the explicit partial-workout Finish regression, all 13 streak tests passed again.
The final unsigned iPhone build-for-testing passed. No interactive app/simulator
UI was used to verify the animation; physical-device visual checks remain open.

Rest protection checkpoint: all 212 unit tests passed with zero failures, including
9 new regressions for rest rules, effective dates, persistence, awards and widget
cache compatibility. The unsigned iPhone app and widget build-for-testing passed.
Physical-device visual checks remain with the project owner.

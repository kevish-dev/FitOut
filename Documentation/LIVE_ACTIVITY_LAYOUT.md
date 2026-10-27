# Lock Screen and Dynamic Island layout repair

The provided IMG_5772.HEIC and IMG_5773.HEIC files were absent at their supplied
Downloads paths. The repair therefore addresses source-proven layout/state risks;
it is not a claim of matching or visually verifying those screenshots.

## Layout

The Lock Screen presentation has three compact rows: exercise/routine with a
labelled total timer, current set/rest with planned targets, and actions. At the
default text size this uses approximately 152 pt rather than stacking last-set,
counts, target, rest and set timers into separate rows. Long titles truncate and
timers use monospaced digits in bounded widths with scaling. VoiceOver retains
both timer labels and their dynamically rendered values.

The expanded Island uses leading status and trailing workout time above a
full-width bottom region. The exercise title no longer competes with two timers
in the center camera region. Below it are the current set/rest and the action
row. Compact trailing width drops from 66 pt to 44 pt; its timer shows rest while
resting and total workout time otherwise. Minimal presentation uses a distinct
state symbol for working, rest, expired rest and pause. The system owns the outer
Live Activity/Island surface; no fake glow or nested opaque card is introduced.

Native intent controls are 44 pt high: icon pause/resume, optional +15 sec, then
one clearly named primary action. A ready set offers Start set; an exercise
transition offers Start exercise; active work opens the workout for actual logging.
Rest offers Skip rest. Expired/stale rest offers Continue, which uses the existing
safe end-rest command to advance. Paused rest shows Resume and Open workout, with
no inactive rest-edit buttons. Existing session/revision/idempotency checks remain.

## State correctness

During rest (including paused rest), projection selects the next pending set and
exercise for the title and targets. It suppresses the completed set's timer.
Optional exercise/set indices, separate prescription, and rest-start timestamp
support clear layout while preserving compatibility with older ActivityKit data.
The total clock remains independent of the current set/rest clock and excludes
paused time. Rest uses system-rendered countdown text over a stable interval,
stopping at zero; foreground code and haptic/notification behavior are unchanged.

Projection normalizes whitespace and bounds text on complete Unicode characters
instead of cutting through a UTF-8 character. Legacy sessions lacking an explicit
execution phase infer a safe ready/working/rest/paused state for presentation.
All values come from saved session snapshots; no sample statistics are shipped.

## Validation

Unit tests cover upcoming-set/exercise projection during rest, frozen paused rest,
stale/expired rest actions, active/ready/empty transitions, old payload decoding,
Unicode bounds and timer formatting. The unsigned iPhone build includes the app
and WidgetKit extension. Real-device Lock Screen/Island layout, gesture behavior,
Always-On rendering, large text, language variants and iOS material rendering
still require owner QA; no interactive simulator or physical-device UI was used.

Layout follows [Apple's Live Activities guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities)
and uses [SwiftUI system timer text](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)).

Checkpoint: all 250 unit tests passed with zero failures, including seven new
Live Activity regressions. The unsigned iPhone app/widget/test build passed.
The initial test run exposed a missing phase in legacy session projection; the
presentation fallback was corrected before the final passing run.

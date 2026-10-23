# Workout routine flow

## Interaction

Home, Gym setup and My Routines share a creation sheet. The initial selection
does not create a routine or draft: the user chooses a blank plan or one of the
five editable templates, compares descriptions and actual training-day counts,
and previews the template's week before continuing. Cancel leaves storage
unchanged. Continue opens the builder inside the same presentation, avoiding a
second sheet or a dismiss/present race. My Routines preserves an existing active
routine when creating another one. Existing plans and drafts open directly.

The builder is one sheet with three stages: Schedule, Workouts, and Review.
Icon-based stage controls stay above the scrolling editor. Stages share one
draft and a fixed bottom action. Changing stages resets scroll
position; choosing a weekday brings its chip into view. Content uses the shared
20 pt page inset, 16 pt section/card spacing, Inter UI text, and restrained glass
surfaces. Set rows use quiet inset fields rather than more glass panels. See
[ROUTINE_DESIGN.md](ROUTINE_DESIGN.md) for the illustrated editor and generated
asset provenance.

- Schedule: name the plan in a labeled field with a visible focus state, select
  training weekdays, leave other days open or
  mark them rest, and optionally choose a start date. Mixed day choices can stay
  as set. Weekday controls use three-letter labels and at least 44 pt tap targets;
  narrower layouts wrap the week, and accessibility text sizes use full weekday
  rows. The bottom action explains missing requirements and becomes available
  after a name and at least one day are set. Removing a training day keeps its
  exercises for later reuse.
- Workouts: switch days in place; edit the name and type; add several exercises
  at once through a searchable, filterable sheet; or create a custom movement.
  Expand an exercise to edit independent sets, default rest, notes, and technique
  instructions. Long-press/drag reorders exercises; menu actions offer accessible
  move-up/down alternatives. Each set can be duplicated, moved, deleted, and
  independently configured for type, rep range, load, rest, and optional effort.
  Timed exercises have seconds and optional distance instead of load/reps fields.
  Loads display in the profile's preferred kg/lb unit and persist in kilograms.
- Workout options: explicitly copy to another weekday, swap with another day,
  save a reusable workout, or reuse one from saved workouts or another routine.
  Copies receive new exercise/set IDs. Overwriting a configured day asks first.
- Review: inspect all seven days, tap a day to edit, choose whether to use the
  routine as active, and save. Missing names, exercises, and invalid set targets
  block completion with a specific message. An incomplete draft is still kept.

My Routines supports editing, template creation (including Arnold Split),
activation, independent duplication, archive/restore, and confirmed deletion.
Reusable workouts are managed in the reuse sheet. Existing saved history is
preserved when a routine is changed, archived, or deleted.

## Recovery and persistence

Drafts are saved after a short typing pause, on Close, when leaving the sheet,
and when the scene becomes inactive. Close stays open if persistence fails.
Interactive dismissal waits until the current draft is stored. Reopening a
routine restores unsaved work and its stage/day; a new unfinished routine can be
continued from Gym setup or My Routines. Discarding a draft is confirmed.

Drafts never change the active saved routine until Save. Committing removes the
draft; activating or archiving another saved plan does not erase pending edits.
Relaunch recovery preserves the current saved plan's activation/archive status.

Schema V5 adds routine-detail, draft, reusable-workout, and session-detail tables.
V1–V4 model definitions remain unchanged and V4→V5 is an additive lightweight
migration. Legacy set-count plans still resolve to their original sets and rep
ranges. Supplemental JSON stores independent targets and day notes without
rewriting old session records. Decoding/storage failures are surfaced rather
than deleting or replacing the user's database.

## Training

Start Workout snapshots the selected day's actual set targets, notes, exercise
order, load, duration, and rest. Unknown movements or invalid/empty plans cannot
silently start a partial session. Each set's rest overrides the exercise default
when present. Target RPE is separate from actual logged RPE, including after
relaunch. Pausing, resuming, finishing, summary, and history use the existing
workout flow. Later edits to the routine cannot change that session snapshot.

Start dates are respected by Home, Gym's daily card, the week rail, and Analytics.
The existing optional AI insight policy excludes independent set configurations
until it has an evidence policy that supports them, preventing misleading advice.

## Verification

Regression test source covers individual-set snapshots, legacy fallback, copy
independence, invalid/timed plans, draft/commit/relaunch, per-set rest and effort,
history preservation, archive recovery, reusable workouts, and V4→V5 migration.
UI test source covers custom setup, adding an exercise, closing/relaunching a
draft, saving, starting the planned session, and finishing it.

The popup changes are checked with Swift parsing, Xcode project validation,
diff whitespace checks, and an unsigned generic-iOS `build-for-testing` of the
app and test targets. The existing UI test flows are updated for template
selection followed by Continue. No app, simulator or device launch, or test
execution is performed. Migration and interaction tests still need runtime
verification on the project owner's testing setup.

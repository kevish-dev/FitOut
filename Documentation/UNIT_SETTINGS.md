# Settings-owned measurement units

Settings → Units is the single place to select weight (kg/lb), height (cm/ft-in)
and water display (ml/L). Pickers save immediately. The full-width weight switches
are removed from active workouts, quick-workout setup and weight onboarding;
height onboarding and water history also no longer show unit switches. Profile
editing shows measurements in the selected units, with preferences in the Units
screen. Onboarding exposes the same Units screen through a compact Settings icon
so imperial preferences can be chosen before entering measurements.

Contextual food serving/base units remain part of food entry: they describe the
quantity being logged rather than a persistent app display preference. Set target,
weight, reps and rest controls likewise remain with their workout inputs.

Weight/height preferences persist through ProfileStore without completing
onboarding or converting stored kg/cm values. A successful change updates the
workout store's observable display preference, widget snapshot and Live Activity
projection. Quick setup, active-session inputs, summaries and analytics use that
preference. Old session unit metadata still decodes and exports but never overrides
Settings. Global unit changes do not save any workout records or rewrite actuals,
planned targets, routines, execution state, rest deadlines or timer anchors.

The weight wheel captures its display unit. Late callbacks from a previous unit
are rejected before canonical values can be changed. Weight/rep input labels
continue to show the current unit. Profile-editor saves retain current Settings
units instead of writing old draft unit preferences back over them.

Water display persists in the existing shared widget store. Home, Nutrition,
water history and widgets resolve the same ml default and selected L preference.
Quick logging and individual water entries retain explicit ml quantities; stored
volumes and goals remain in milliliters. No storage schema or dependency is added.

Validation: all 289 unit tests passed, including four new regressions for disk
persistence with unfinished onboarding, app/profile/workout/widget synchronization,
late callbacks, and water preference persistence without changing logs/goals.
Live Activity tests verify Settings overrides legacy session units. The unsigned
iPhone build-for-testing passed. Onboarding/settings layout and picker interaction
remain for the owner to check on iPhone; no interactive UI automation was run.

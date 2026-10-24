# Minimal component motion

Component motion uses two shared FitMotion timings: 120 ms ease-out for press
feedback and 180 ms ease-out for routine state changes. Reduce Motion returns no
custom animation; visible color/opacity state and native control feedback remain.

The existing shared press style now uses a gentler 1.5% compression and 10%
opacity change, also applied to onboarding Back/Next, nutrition primary actions
and hydration quick logging. Native tab/glass interactions retain their own effects.

Exercise selection and filter highlights crossfade. Selection counts update
numerically, and expanding the selected-exercise tray uses a short fade. Quick
workout exercise/set insertions and removals fade, with stable IDs preserving
edit buffers and focus. Reordering uses the same short transition. Set counts,
hydration totals/progress and the weekly workout-volume number animate only when
their underlying values change. Onboarding step bars transition their colors.

Animations are attached to their specific state values and components. Search
input, numeric text fields, workout clocks, scrolling and page entrances get no
new animation. There are no delays, repeating tasks, idle effects or new assets.
The existing streak celebration remains the intentional focal animation.

Validation is an unsigned generic-iOS build-for-testing plus source/Swift parse
and whitespace checks. No UI automation or new state/persistence tests are added
for these reversible visual changes. Device motion/performance checks remain with
the project owner.

# Home dashboard

Implemented directly from the updated reference mock (`media_1792768403220_fb9182ab.png`) and FitOut brand guidelines.

## Layout & Architecture

1. **Hero Header**:
   - Left: "Hi [Name]," (bold white) with a subtle settings gear shortcut, followed by "Welcome!" (heavy bold #FF4D00 orange).
   - Right: Fixed circular menu control that expands five navigation buttons (Home, Gym, Nutrition, Health, AI Coach).
   - Active button displays a vibrant orange glowing border and an indicator dot on its top-right corner.

2. **Workout Routine CTA Card**:
   - Dark frosted glass card (`.ultraThinMaterial` over dark surface with 20pt corner radius).
   - Left: Circular badge with radial orange glow and dumbbell icon.
   - Center: "Set up your workout routine" with description "Get a personalized plan based on your goals" (or today's planned/active workout details).
   - Right: Circular deep-orange gradient button with right chevron arrow that launches routine creation or today's session.

3. **Weekly Workouts Tracker**:
   - "Workouts" header with diagonal arrow navigation link to `AnalyticsView`.
   - 7 weekday circles (Sunday to Saturday):
     - Completed workout: Emerald green circular badge with checkmark (`#22C55E`).
     - Rest day: Dark circular badge with crescent moon icon (`moon.fill`).
     - Missed scheduled workout: Crimson red circular badge with X (`#EF4444`).
     - Day initials ("S", "M", "T", "W", "T", "F", "S") below each bubble.
   - Bottom statistics:
     - Left: Completed sessions count (e.g. "3/4 Completed this week").
     - Divider line.
     - Right: Percentage on track (e.g. "85% On Track").

4. **Workout volume progression**:
   - A six-week bar history sits below the weekly workout tracker.
   - The large readout is this week's completed weighted load × reps, in the user's selected weight unit.
   - The current week is orange; previous weeks are muted, including empty weeks. Last week's total is shown separately without treating the in-progress week as a completed comparison.
   - Only completed weighted sets count; warm-ups, unfinished sessions, and future-dated sessions are excluded.
   - The arrow opens detailed Analytics. With no weighted volume yet, the card offers a link to Gym.

5. **Optional workout insight**:
   - One short fact and a review action appear only when the on-device Foundation Model is available and selects a supported insight.
   - Evidence requires three completed workouts on distinct days spanning at least a week, with the latest within seven days, an unchanged active plan, consistent loads, and complete working sets with effort logged.
   - Supported signals are repeatedly reaching the current rep ceiling at effort ≤8/10, or repeatedly falling below the current rep floor at effort ≥9/10.
   - The model chooses from verified statements or declines; its free-form prose is never shown. Model failure, insufficient data, unavailable AI, and invalid output leave no section or placeholder. Selection runs only while Home is active, and changes to the plan or evidence invalidate the previous result.
   - Review progression opens Analytics with the relevant exercise selected.

6. **Daily health overview**:
   - A 2-column set of quiet, rounded panels with different visual histories instead of four identical number/progress-bar cards.
   - **Water intake**: Logged liters and 2-hour log bubbles.
   - **Steps**: Today's count and a 2-hour pace trace.
   - **Active calories**: Active energy burned and 2-hour movement-energy bars.
   - **Sleep**: Last night's asleep duration and a 12-segment timeline.
   - The section uses Apple Health readings already shared with FitOut. Empty readings show a clear missing-data state; the section links to Health access and supports pull-to-refresh. No personal goals are inferred from the artwork.

## Background Asset

Full-screen cinematic fitness background (`HomeAthlete` asset) featuring a muscular martial artist executing an explosive high kick toward the left with glowing fiery orange energy trails and embers, matching the visual aesthetic of the reference mock.

## Current behavior after navigation and data correction

The Home scroll view owns the greeting, so it moves away with the cards.
The shell overlays only the circular navigation control at the top right.
It uses a menu icon when collapsed and a close icon when expanded; Home has
its own house icon in the destination list. Tapping the control opens five
destination buttons directly below it; choosing a destination closes the
menu. Settings is reachable at the bottom of Home.

A responsive 340–480 pt clear hero area exposes the background before the
routine card, weekly calendar, and metric grid. All dashboard cards scroll;
only the navigation control stays fixed. Long routine titles can wrap.

The numeric values above describe the supplied visual reference, not saved
user data. Production uses actual workout counts and routine targets. Day
labels follow the user's calendar. Skipped or abandoned sessions are marked
explicitly; unlogged past days are not assumed missed or rest days. An active
workout is shown as in progress, not completed. The health overview reads
water, steps, active energy burned, and sleep from Apple Health when available.
No reading remains distinct from an actual zero reading.

This update was reviewed in source only. No build or runtime check was run.

## Liquid Glass refinement

The navigation circles, routine action, weekly summary, and Settings shortcut
share a glass surface. iOS 26 uses native Liquid Glass;
earlier supported versions use frosted material with a subtle highlight.
Reduce Transparency replaces both with an opaque charcoal surface. The
menu is anchored to the Home button rather than a fixed screen offset,
and Reduce Motion disables its opening animation. There are no bottom tabs.

The background image now fits the screen width, so the athlete's extended
kick and body are not cropped by a full-screen fill. The first card begins
below the pose, and the dark fade starts near the bottom of the image.
The background overlay is lighter below the hero, with less glow on the
routine card. Cards use consistent rounded contours and 16 pt vertical
spacing. The metric panels use quieter opaque surfaces so their visual
histories stay readable over the athlete background.

The latest HEIC reference could not be decoded locally. These refinements
use the earlier dashboard reference and source inspection. No build,
simulator, device launch, or runtime visual verification was performed.

## Background replacement

`HomeAthlete` now contains the supplied “Fiery Kick in the Shadows” image.
The Home scroll view draws that asset directly behind its content, so the
navigation container cannot leave an opaque black gap below the greeting.
The fixed header row was removed to keep the photo and content aligned.

In debug builds, a Start Over (Testing) button appears below Settings.
After confirmation it saves a fresh onboarding profile and returns to the
opening screen. Workout history and routines remain saved; the optional
Apple Health explainer can be shown again after onboarding.

The routine card prompts setup until the active routine has at least one
scheduled workout day. The prompt edits an existing empty routine if present.
Once configured, the card shows today's scheduled workout, rest day, or
flexible day; a quick workout does not replace the setup prompt.

The streak card sits immediately below the routine card as a short, wide
rectangle. It uses three horizontal zones: streak and flame, seven daily
completion markers, and the current week's count. The flame is a separate
asset; numbers and checks come from completed workout history.

Custom pages share a 20 pt horizontal page inset and a 16 pt section/card
spacing scale. On Home the greeting, routine, streak, weekly tracker, metrics,
and fixed navigation control align to that inset. The streak's inner columns
shrink on narrow phones so all seven day markers remain visible.

## Health reload correction

Home and the Health connection page observe a shared Health overview. Fresh reads
run when those pages appear, when the app becomes active, after every successful
permission review, and on pull-to-refresh. Home also refreshes at a calendar day
change. Health includes a Reload Health Readings button and the last-check time.

The local setup preference no longer blocks queries: it records request completion,
not evidence of HealthKit read permission. Daily steps and active-energy totals
are queried independently of their two-hour charts, and a newer reload takes
precedence over an older in-flight response. Query errors remain visible as
errors; missing shared samples and actual zero readings remain distinct.

The Calories tile now explicitly shows active energy burned, rather than food
calories consumed. It does not add resting energy or substitute food intake.
HealthKit can still return no shared samples when there is no data or read
access is withheld; FitOut does not claim it can distinguish those cases.

Regression test source covers repeated reviews, missing setup preferences,
updated and zero readings on reload, local-day boundaries, unavailable Health,
query errors, and out-of-order reads. Static checks do not verify device readings.

## Shared dashboard scrolling

Home and Gym use the same `DashboardScroll` container in the design system.
Header and content scroll together over a fixed full-screen background. Both use
the same responsive hero clearance, content width, margins, bottom inset,
indicator visibility, vertical bounce, and pull-to-refresh interaction. Only the
shell navigation stays fixed. Home keeps the kick image; Gym uses its own athlete.

# Home dashboard

Implemented directly from the updated reference mock (`media_1792768403220_fb9182ab.png`) and FitOut brand guidelines.

## Layout & Architecture

1. **Hero Header**:
   - Left: "Hi [Name]," (bold white) with a subtle settings gear shortcut, followed by "Welcome!" (heavy bold #FF4D00 orange).
   - Right: Pinned vertical navigation rail of 5 circular buttons (Home, Gym, Nutrition, Health, AI Coach).
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

4. **2x2 Health & Activity Metrics Grid**:
   - Equal 2-column grid of frosted glass cards:
     - **Water Intake**: Water droplet icon, "1.5 / 2.5 L", 60% orange capsule progress bar. Links to Nutrition.
     - **Steps**: Footprints icon, "5,000 / 7,000", 71% orange capsule progress bar. Links to Health.
     - **Calories**: Flame icon, "1,250 kcal", 62% orange capsule progress bar. Links to Nutrition.
     - **Sleep**: Moon icon, "7h 20m", 80% purple-to-blue gradient capsule progress bar. Links to Health.

## Background Asset

Full-screen cinematic fitness background (`HomeAthlete` asset) featuring a muscular martial artist executing an explosive high kick toward the left with glowing fiery orange energy trails and embers, matching the visual aesthetic of the reference mock.

## Current behavior after navigation and data correction

The Home scroll view owns the greeting, so it moves away with the cards.
The shell overlays only the circular navigation control at the top right.
Tapping it opens five destination buttons directly below it; choosing a
destination closes the menu. Settings is reachable at the bottom of Home.

A responsive 340–480 pt clear hero area exposes the background before the
routine card, weekly calendar, and metric grid. All dashboard cards scroll;
only the navigation control stays fixed. Long routine titles can wrap.

The numeric values above describe the supplied visual reference, not saved
user data. Production uses actual workout counts and routine targets. Day
labels follow the user's calendar. Skipped or abandoned sessions are marked
explicitly; unlogged past days are not assumed missed or rest days. An active
workout is shown as in progress, not completed. Health/nutrition cards show
no reading/logs and empty progress tracks until those data sources exist.

This update was reviewed in source only. No build or runtime check was run.

## Liquid Glass refinement

The navigation circles, routine action, weekly summary, metric cards, and
Settings shortcut share a glass surface. iOS 26 uses native Liquid Glass;
earlier supported versions use frosted material with a subtle highlight.
Reduce Transparency replaces both with an opaque charcoal surface. The
menu is anchored to the Home button rather than a fixed screen offset,
and Reduce Motion disables its opening animation. There are no bottom tabs.

The background image now fits the screen width, so the athlete's extended
kick and body are not cropped by a full-screen fill. The first card begins
below the pose, and the dark fade starts near the bottom of the image.
The background overlay is lighter below the hero, with less glow on the
routine card. Cards use consistent rounded contours and 16 pt vertical
spacing. Metrics continue to represent real or unavailable data.

The latest HEIC reference could not be decoded locally. These refinements
use the earlier dashboard reference and source inspection. No build,
simulator, device launch, or runtime visual verification was performed.

## Background replacement

`HomeAthlete` now contains the supplied “Fiery Kick in the Shadows” image.
The Home scroll view draws that asset directly behind its content, so the
navigation container cannot leave an opaque black gap below the greeting.
The fixed header row was removed to keep the photo and content aligned.

# Gym landing page

The Gym tab uses FitOut's bundled athlete image, Orbitron headlines and metrics,
Inter interface text, charcoal surfaces, and restrained orange accents. The
shared shell continues to own the fixed top-right navigation. The page header
and all sections scroll, using the shared page, section, and card spacing.

Home and Gym now use the same `DashboardScroll` container: a fixed full-viewport
athlete background, scrolling header and cards, matching responsive hero spacing,
20 pt side insets, 560 pt content limit, hidden indicators, vertical bounce, and
pull-to-refresh. Gym keeps its lifting image. Its refresh action reloads routines
and sessions from local storage; Home refreshes the Health readings.

## Daily card

- An unfinished session offers Resume, including after relaunch or midnight.
- Without an active routine containing workout days, the card offers setup.
  Setup edits an existing empty active routine or offers editable templates and
  a custom plan. New plans created here become active when saved.
- A scheduled workout shows its actual title, exercise count, optional duration
  target, and selected muscles. Start uses the saved plan and catalogue.
- Scheduled days without exercises open the day editor instead of starting an
  empty planned session.
- Rest and unassigned days open the weekly plan. A separate freestyle action
  starts an unscheduled session, or resumes the existing session.
- A completed session belonging to today's routine offers its saved summary.
  A freestyle session does not hide a scheduled workout that remains to be done.
  Scheduled completion uses the session's start day, so an overnight session
  does not also complete the next day's plan.

## Destinations and weekly overview

Weekly Plan opens the active routine editor. My Routines retains routine
creation, editing, activation, duplication, and confirmed deletion. Exercises
opens the existing searchable library and custom exercise flow. Workout History
and Analytics open their existing saved-data views.

The horizontal week rail always runs Monday through Sunday and includes dates,
today's highlight, workout names, exercise counts, and explicit statuses.
Previous/next controls browse weeks; Today returns to the current week.
Tapping a logged session opens its summary or resumes it. Other days open the
matching weekday in the repeating routine editor, with a Save action. Past days
without a log are not marked missed or reconstructed from today's routine.

## Progress and scope

Progress uses completed, nonfuture sessions in the current Monday-based week:
session count, weighted volume in the preferred unit, and logged sets. Volume
excludes warm-ups. The initial state explains that a completed workout is needed;
it shows no sample totals, attendance percentages, or invented records.

The landing page now connects to the complete routine builder described in
[Workout routine flow](ROUTINE_FLOW.md), including drafts and independent sets.
Syntax, isolated type checks, project-file validation, and whitespace checks are
used for verification. No app, simulator, or device run is performed.

## Liquid Glass

The daily card, toolkit shortcuts, weekday tiles, progress panels, week arrows,
week-reset control, edit-plan action, and analytics shortcut share the existing
Liquid Glass modifier. Interactive controls opt into its interaction treatment.
The primary start/setup action retains a solid orange fill for clear emphasis.
The fixed shell navigation already uses the same glass treatment. iOS 26 uses
native glass; earlier iOS versions use material, and Reduce Transparency uses
opaque charcoal surfaces with visible borders. Fonts and spacing are preserved.

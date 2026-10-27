# Gym routing and rest-day regression

The routine editor's scroll lifecycle, draft-only autosave and stable-ID editing
follow-up is documented in [Routine editor stability](ROUTINE_EDITOR_STABILITY.md).

Weekly Plan opens the complete Schedule stage, even when today is Rest/Open or a
saved draft last opened on Review. A calendar-day tap explicitly opens that day's
Workouts editor, including rest/open days, where its kind can be changed. Resuming
a draft without an explicit entry intent preserves its saved stage and weekday.
The saved-routine list opens Schedule; its Continue Editing rows resume the draft.
Invalid saved weekday indices fall back to today's valid weekday.

Quick Workout is independent of the selected routine day. On workout, rest, open
or unscheduled days it opens configuration without creating a session. If a
workout is already active/paused, the same entry resumes it. Rest/open/empty days
cannot be passed through as empty planned workouts; their actions open the day
editor instead. Starting a quick workout on a rest day never changes the saved
routine's rest setting. Workout widget start links fall back to Quick Workout
configuration when there is no startable scheduled workout; stale current-workout
links also remain actionable by opening configuration.

Gym now owns one identified modal destination for workout, routine, creation or
summary. While occupied, repeated/competing requests cannot swap its content.
Dismissal releases that slot before the next action. My Routines also uses one
identified edit/create destination. Modal errors do not compete with Gym's root
alert. Existing detail navigation links (library/history/analytics) use their
native NavigationStack.

Native TabView callbacks no longer share the explicit corner-menu reselect action.
Repeated system selection callbacks previously changed a UUID used to identify the
entire section, risking teardown of its presented sheet. AppTabNavigation ignores
same-value system callbacks, preserves existing stack identities while switching,
and resets a root only for an explicit same-section corner-menu action.

Regression tests cover every weekday with rest/open plans, forced schedule vs
draft/day entry, creation fallback, repeated competing presentation attempts,
dismiss/reopen, invalid saved weekdays, repeated native tab callbacks, and a real
quick-workout start/pause/resume/completion on a rest day with the routine unchanged.
Rest/open days are also verified to reject empty planned sessions.

The full 203-test unit suite passed. Final generic-iOS build-for-testing compiles
the app, widgets and test targets. No interactive UI automation was run; these
checks validate the state/routing fixes without claiming a manually reproduced
physical-device freeze. Device presentation/touch verification remains necessary.

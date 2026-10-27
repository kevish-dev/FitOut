# Routine editor stability

Switching Schedule/Workouts/Review retains one vertical ScrollView and its pinned
stage/action bars. The previous `.id(stage)` recreated that complete hierarchy
while a step's matched-geometry animation and immediate day-strip `scrollTo` ran.
The editor now resets the top edge through a native ScrollPosition, and both the
editor and Gym calendar use declarative horizontal scroll positions. No Gym
ScrollViewReader performs a synchronous scroll during appearance. Step/day-kind
feedback animates the fixed control only, without animating the entire editor.
Selecting an already-selected stage/day/kind is a no-op. The selected day remains
separate from the visible horizontal scroll target, so swiping the day strip does
not change which day is being edited.

Draft autosave updates only its DraftRecord and observable draft list. Identical
routine/stage/weekday content skips encoding, persistence and notification even
if its incoming timestamp differs. Successful draft writes do not reload the
catalogue, committed routine or saved workouts, and do not call the committed-plan
change callback that republishes widget state. Explicit routine commits retain
their full persistence and notification path. Editor autosaves remain debounced,
and close/background persistence retains the latest draft.

Day, exercise and planned-set bindings resolve stable IDs on every read/write.
A removed row supplies its original value while SwiftUI tears it down and ignores
late writes, avoiding an obsolete collection offset or edits to its replacement.
Changing days dismisses the keyboard and resets only the selected day's content.
Exercise cards load lazily. Missing draft days show a recovery message; invalid
weekday labels/targets are guarded without deleting saved data.

Add/replace/reuse/copy/move/muscle sheets capture the day ID that opened them.
A competing open request cannot replace the active sheet. Callbacks resolve that
same day even after reordering, and missing targets are rejected. A stale replace
callback does not append an exercise to a different day. Reuse confirmation also
retains the destination day ID instead of reading the current weekday later.

Verification: all 297 unit tests passed, including eight new regressions covering
rapid day/stage saves, draft-only disk persistence, reordered day bindings,
deleted exercises/sets/parents, rest/open days and picker target identity. The
unsigned iPhone app/widget/test build passed without compiler warnings. Value
types used by the shared binding explicitly conform to Sendable; no persistence
schema, backend or dependency is added.

These are source-level fixes for the risky navigation, update and binding paths;
the current physical-device hang was not interactively reproduced. The owner
should test opening an existing routine, repeatedly switching all three steps and
all seven days, then editing/removing/reordering sets and adding/replacing
exercises. Close/reopen should restore the draft without modifying the saved plan
until Save. No computer-use or interactive UI automation was run.

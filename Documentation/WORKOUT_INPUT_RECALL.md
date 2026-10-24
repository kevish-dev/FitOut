# Workout input recall

Quick and planned workouts use the same saved performance history. Defaults
reduce typing while actual set completion remains an explicit action.

- Adding or replacing an exercise recalls confirmed inputs for that exercise ID,
  exercise kind and set type. Working sets, warm-ups and drop sets stay separate.
  Repeated entries can use already logged sets from the current workout. Otherwise
  the most recently performed matching entry supplies the corresponding set of
  that type; extra sets fall back to its last confirmed set. Unlogged, invalid and
  skipped-session data do not supply defaults. Valid sets from an abandoned
  workout remain usable.
- Quick workouts recall load/reps, bodyweight reps, or timed seconds/distance, plus
  rest. Planned workouts fill unspecified loads; explicit loads (including zero),
  rep targets, duration/distance targets and rest prescriptions stay in place.
- Logging a set carries manually changed inputs forward to later, untouched sets
  of the same type. Logging unchanged defaults preserves previous per-set values.
  Manually edited fields are protected independently and persist across reloads.
  A changed upcoming load does not prevent its untouched reps being filled.
  Logged sets and sets whose timer has started are never changed by defaults.
  Correcting a previously logged set does not silently rewrite upcoming inputs.
- Add set copies the last working set's inputs and rest into a new working set.
  It does not copy effort, completion, measurement anchors or prescription targets.
  If only warm-ups exist, working-set history supplies defaults when available.
- Each set displays its previous values and date, or the preceding confirmed set
  from this workout. Use previous explicitly copies inputs into an unlogged,
  unstarted set. Original prescription metadata stays visible for comparison.
  There is no empty reference or invented history for a first-time exercise.
- The set options menu offers Apply weight to remaining sets for weighted
  exercises, retaining each set's rep target. Bodyweight and timed exercises can
  repeat their relevant inputs. This explicit action can override upcoming edits
  and targets for this session; it skips other set types and started/logged sets.
  The saved routine remains unchanged.
- Numeric fields retain direct keyboard editing and add repeating +/- controls:
  2.5 kg / 5 lb for load, 1 rep, 5 seconds, and 50 meters. Adjustments are bounded
  by the existing supported ranges. Layout stacks at narrow widths and larger
  text sizes. Weights remain stored in kg, so unit changes do not alter recall.
- No suggestion copies RPE, completed timestamps, set timers or measured evidence.
  The existing telemetry captures manual copies, adjustments and carried defaults.
  Supplement-only optional fields preserve old SwiftData schemas. A workout that
  was already active before this feature conservatively protects its existing
  pending inputs; Use previous remains available to change them explicitly.

Regression sources cover recall across reload, per-type/ordinal matching,
prescriptions and explicit zero, manual field protection, invalid/absent history,
current-session reuse, replacement, fresh sets, timer protection, bulk changes and
legacy active-session preservation. Generic-iOS `build-for-testing` compiles those
sources along with the app and widgets. Tests and the app are not executed.

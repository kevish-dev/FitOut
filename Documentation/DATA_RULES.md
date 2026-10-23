# Deterministic data rules

- Dates are stored as absolute timestamps. Day/week summaries use the user's current Calendar/time zone, with explicit calendar injection in tests. Routine weekdays are Monday=0 through Sunday=6; Apple weekday values are converted rather than used as array indexes.
- Canonical mass is kilograms and height/length is centimeters. Unit selectors convert display values and never mutate the underlying measurement merely by switching units.
- A routine has one entry for every weekday. Rest and flexible days retain their exercise configuration if temporarily toggled. Moving a day swaps two weekday assignments. At most one routine is active.
- Built-in exercise definitions and user-selected routine templates are catalogue content, not user workout records. Production never seeds completed sessions or health/nutrition entries.
- Completed workout history will store independent snapshots of exercise names, muscles and tracking kinds. It must not derive historical data from the current routine or exercise catalogue.
- Workout active duration excludes paused time. Rest timers use absolute deadlines so backgrounding does not extend a timer.
- Qualifying training volume will sum completed working/drop weighted sets as kg × reps. Warm-up, bodyweight and duration-only sets remain separately recorded and do not contribute to comparable weighted volume.
- Estimated 1RM will use Epley for 2–10 reps (load × (1 + reps/30)); a single rep uses the actual load. It is an estimate, never a prescribed working load. Invalid/zero loads and nonweighted sets are excluded.
- HealthKit request completion is not read authorization. Imported identifiers are deduplicated, and Apple Health nutrition stays visibly separate from manual totals unless an explicit source-selection policy says otherwise.
- Missing targets/readings are absent values, never fabricated zero measurements. Logged numeric zero is distinguishable from no record.

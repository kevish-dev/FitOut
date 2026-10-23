# Food & Nutrition

The Nutrition destination now provides the initial local-first module end to end. It uses FitOut's existing Inter/Orbitron typography, 20 pt page margins, shared spacing, dark surfaces, restrained orange and native glass controls. The page scrolls beneath the same fixed navigation menu as the rest of the app. Most workflows use sheets and progressive disclosure rather than additional full-screen destinations.

## Working flows

- **Daily diary:** select today or an earlier date, view calories/macros, and open breakfast/lunch/dinner/snacks. Unknown totals appear as unavailable; partially known totals are labelled. Remaining/above-target calories are shown only when the logged energy values are complete.
- **Food logging:** search by food, brand, aliases or Indian names; browse recents/favorites; choose a defined reference amount, grams/ml where supported, or a named portion. Fractional quantities scale all available nutrients. Raw and cooked records are distinct; no automatic raw/cooked or mass/volume conversion is invented.
- **Corrections:** edit an entry's amount, meal, timestamp, note or nutrition snapshot. The correction applies to that entry. Move entries between meals without changing their timestamp. Duplicate an entry, repeat the last entry, copy a meal from another date, or delete and undo the last deletion.
- **Custom foods:** create, edit and delete foods with reference quantity/unit, available nutrients, brand, preparation, aliases and defined named servings. Make a separate editable copy of reference data. Missing nutrients stay missing; quick-add requires calories and identifies itself as manual totals.
- **Recipes:** combine ingredient snapshots, edit ingredient portions, set serving yield and optionally finished cooked weight. Log by serving, whole recipe or grams of the finished recipe when its weight is known. Partial ingredient nutrition remains partial. Changing/deleting a recipe leaves previously logged snapshots intact.
- **Reusable meals:** save a diary meal or build a food combination. Edit/delete it, then log its individual portions to a chosen meal/date.
- **Targets:** set or skip calories, protein, carbohydrates, fat and other supported nutrients. Target versions apply from the chosen date until the next change; earlier goal versions remain available. The app does not infer targets from a fitness goal or credit exercise calories automatically.
- **Hydration:** the app, Nutrition, Home and widgets share FitOut water entries and optional goal. Log preset/custom amounts, edit quantity/date/time, remove/undo, browse previous dates and choose ml/L. Today can include shared Health water; historical water views explicitly show FitOut logs only. Local water is not exported to HealthKit, avoiding a duplicate on the next read.
- **Reminders:** one optional local daily water reminder at the user's chosen time. Notification authorization is requested only after saving an enabled reminder. Users can disable it; OS permission changes are reflected on return. Creating/building this module does not schedule a reminder.
- **History:** seven- or thirty-day charts for calories, protein, carbohydrates, fat and FitOut water. Charts show actual records, partial-value bars and per-date configured targets. Averages require at least three logged days with complete values for that metric and explicitly exclude unlogged days. Macro energy distribution uses only days with complete P/C/F values, labels its 4/4/9 calculation and does not rewrite database calories.
- **Context and insights:** actual scheduled gym training is shown where available. Protein remaining is based on the configured target and complete logged protein. Weekly summaries appear only with enough complete logged days. No generic AI text or medical conclusions fill empty space.
- **Privacy:** export JSON containing user food records, historical snapshots, recipes, saved meals, target versions, favorites and FitOut water. Delete nutrition data independently of workout/profile data, or delete FitOut water history separately. No account or network connection is required for core logging.
- **Nutrition widget:** a ninth widget shows food kcal logged, optional targets, and macros as size permits. It distinguishes energy consumed from the existing active-energy-burned widget. Estimates get an approximation marker, missing data stays unavailable, and yesterday's cached totals do not carry into today. Tapping opens the Nutrition diary.

## Offline food data

`NutritionFoods.json` bundles **104** foods:

- 91 exact nutrient records selected from **USDA SR Legacy, April 2018**, with NDB identifiers, original descriptions, documented portion weights and source attribution. This is a dated reference snapshot, not a promise that every current branded package has identical values.
- One published, approximate **Amul Fresh Paneer** composition from the manufacturer/co-operative's product page. It is brand-specific, dated and labelled as a published product reference; users are asked to check their actual pack.
- 12 explicitly marked **recipe estimates** covering common Indian preparations, including homemade roti, paratha, idli, dosa, poha, upma, dal, rajma, chole, khichdi, sabzi and a paneer rice bowl. Their ingredient/finished-yield assumptions are visible. Unmeasured added salt is not silently recorded as zero sodium. Poha explicitly identifies the rice-equivalent approximation used for flakes.

All values remain editable in a logged snapshot or custom copy. The app never labels the prepared-food estimates as verified measurements. Unknown nutrients are omitted/null, not zero. Calories are retained from the source rather than forced to match macro-derived energy.

Source archive: [USDA's dataset catalogue](https://catalog.data.gov/dataset/usda-national-nutrient-database-for-standard-reference-legacy-release), [SR Legacy ASCII archive](https://ndownloader.figshare.com/files/43633731). USDA FoodData Central data is [public-domain / CC0](https://fdc.nal.usda.gov/). Paneer source: [Dudhsagar Dairy's published product composition](https://dudhsagardairy.coop/dairy/products/amul-fresh-paneer/), checked 24 Oct 2026.

`Scripts/build_nutrition_catalogue.py` reproducibly builds the bundled subset from that archive; it does not run in the app. `NutritionFoodSearching` is the boundary for a future external verified provider. There are no API keys, runtime catalogue downloads or requests to third-party AI services.

## Persistence and compatibility

Schema V6 adds food, entry, recipe, saved-meal, target and settings payload records through a lightweight V5 → V6 migration. All previous schema definitions are retained. Food-log portions and recipe ingredients contain immutable-by-copy food snapshots, preserving historical quantities, values, preparation and provenance after library edits/deletions.

Hydration continues to use the atomic, process-locked widget store. A local Application Support fallback allows water logging without a working App Group; logs are merged into the group by ID if it becomes available. Imported IDs prevent repeated migration or resurrection after a later deletion. Widget cache additions are optional to decode old caches. App/food functionality does not require HealthKit; widget installation still requires the App Group to be provisioned for both targets.

Food logs and targets are grouped using local calendar days, including DST boundaries. Imported Health water is not claimed to be a complete historical hydration record. Food-derived energy remains separate from Health active energy.

## Verification and remaining phases

The iPhone app, embedded widgets, unit-test target and UI-test target compile with signing disabled. Tests are **built, not executed**; no app, simulator or device was launched. `NutritionTests` covers scaling, missing nutrients, recipe yields, historical snapshots, CRUD/reopen, target versions, meal copying, deletion isolation, catalogue provenance, V5 migration, water editing and old widget-cache decoding.

For device QA, exercise Add Food → portion → save → relaunch; repeat/edit/move/delete/undo; custom food edits with existing history; recipe yield/gram logging; saved meals/copying; target changes on past dates; empty/partial/above-target states; water editing/units/widget updates; notification denial/enable/disable; history and export/delete. Check small screens, larger text, Reduce Transparency and widget sizes/tinted appearance. Provisioning and visual/runtime behavior require device/Xcode checks by the project owner.

As phased in the brief, external verified search, barcode scanning, photo recognition, dietary HealthKit synchronization and nutrition-grounded AI retrieval remain future enhancements. There are no nonfunctional buttons suggesting those features already exist.

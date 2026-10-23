# FitOut widgets

Nine WidgetKit widgets are included in the embedded `FitOutWidgets` extension: water, today's workout, steps, active energy, sleep, workout streak, training volume, daily overview and food/macros. They use the app's Inter/Orbitron fonts, minimal surfaces and restrained orange accents, with system-adaptive backgrounds and tinted rendering.

## Sizes and actions

| Widget | Small | Medium | Large | Extra large |
| --- | --- | --- | --- | --- |
| Water | Today's intake | Intake, +150/+500 ml | Four quick amounts, exact-entry undo, history link | Large controls and seven-day FitOut water history |
| Workout | Current workout or setup/rest/completed state | Open/start/resume/view plan | Exercise preview plus the appropriate action | Expanded preview and edit-plan shortcut |
| Steps / active energy / sleep | Latest synced reading and optional goal | Reading, goal and Health shortcut | Recorded activity/sleep chart where data exists | Larger chart and details |
| Streak | Consecutive days and week marks | Week marks and history shortcut | Day labels and weekly completion count | Expanded week overview |
| Volume | Current weighted weekly volume | Prior-week change when meaningful and analytics shortcut | Six-week volume chart | Larger progression chart |
| Overview | Water and steps | Water, steps, active energy and sleep | Four readings, current workout action and water logging | Weekly streak and progression shortcuts as well |
| Food & macros | Food kcal logged | Calories, optional target and diary shortcut | Protein/carbs/fat and partial-data labels | Expanded nutrient overview |

All nine also offer circular, rectangular and inline Lock Screen families. Rectangular water/overview widgets add a +150 ml button; circular/inline remain glanceable. WidgetKit determines which sizes are available on a particular device/context. The extension targets iPhone and iPad, including the iPad extra-large family, while retaining the app's existing iOS 18 minimum. Platform availability is not a claim of a separate watchOS/macOS app.

Layouts use flexible columns, limited line counts, scaled metric text and vertical `ViewThatFits` fallbacks so extra detail gives way before actions overflow. Larger water layouts fall back to two amounts under severe space constraints. No widget contains a scrolling list or text field. Health and training content is marked privacy-sensitive; the system controls redaction and unlock requirements.

## Real data and behavior

- Widget actions and app water logging share an App Group JSON store with atomic file replacement and a process-shared file lock. Publishing a new app snapshot preserves water logs and goals. Undo addresses the exact displayed log ID and is safe to repeat.
- Water logged here is local to FitOut. Today's total adds local entries to Apple Health water shared with the app. FitOut does **not** export these local entries to HealthKit, avoiding an app-created duplicate on the next Health read. App Home and Water intake show the same logs; entries can be removed from water history. The extra-large history shows local FitOut entries only.
- Optional personal goals are under Settings → Widgets & goals or Water intake → Widget goals. No health target is invented or inferred from a profile.
- Health widgets show cached readings, their sync time, and an honest missing-data state. They do not infer read permission from the connection preference. Health queries happen in the main app on activation, refresh and permission review. These widgets do not promise live step or energy updates while the app is closed.
- Workout links are revalidated against the current active session, today's actual routine and completed history when the app opens. A stale Start link cannot start yesterday's/rest-day plan or duplicate a completed scheduled workout. Active sessions open or resume; absent routines open the actual routine editor. Exercise previews are capped to fit.
- Streaks use completed workout dates, credit one day regardless of session count, tolerate yesterday as an ongoing streak, and reset after a missed day. Weighted volume uses the existing analytics rules and honors kg/lb preference.
- Providers schedule midnight entries to stop showing yesterday's Health totals and recalculate water/streaks. They request a fresh cache read after 30 minutes; iOS chooses the actual refresh schedule. App data changes and water actions request immediate timeline reloads.
- Missing App Group access, unreadable data and newer data versions are handled without deleting or replacing saved data. UI-test defaults do not publish to production widget storage. The existing SwiftData database stays in its original location.

## Signing and adding widgets

Both **FitOut** and **FitOutWidgets** declare `group.com.kevishsewliya.fitout` in their App Groups entitlements. The extension is a target dependency and is embedded automatically in the app. In Xcode, select the same developer team for both targets, keep automatic signing enabled, and verify that this App Group is registered and selected under Signing & Capabilities for both. The account/provisioning profile must support App Groups; an unsigned build does not validate provisioning on a device.

Build and install FitOut, then open it and finish onboarding at least once. On iPhone, hold the Home Screen → Edit → Add Widget → FitOut. Resize or add another size to reveal the appropriate controls. Lock Screen widgets are added from Lock Screen customization. Widget availability/refresh timing is managed by the OS.

## Verification

The iPhone-target build was compiled with signing disabled. No app, simulator or tests were launched. `WidgetTests` adds regression coverage for daily resets, DST streak counting, goal validation, exact-entry undo, shared-state preservation, corruption protection, routes and week boundaries. Their source is type checked; execute them and visually check actual widget sizes/tinted/StandBy/Lock Screen appearances on devices in Xcode.

Implementation follows Apple's [interactive widget guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [extension and link guidance](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension) and [timeline refresh rules](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

The Nutrition module adds date-based water editing/history and a shared ml/L display preference. Water has a local Application Support fallback when App Groups are unavailable and merges by log ID when sharing becomes available. The nutrition widget uses actual diary snapshots and explicitly marks estimates and incomplete values. See [NUTRITION.md](NUTRITION.md).

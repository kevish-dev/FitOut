# Personal iPhone Fitness App --- Product Requirements Document (PRD)

**Version:** 1.0\
**Status:** Implementation baseline for coding agents\
**Platform:** iPhone / iOS only\
**Primary user:** One person (single-user, personal app)\
**AI strategy:** Apple-native frameworks only for the initial
implementation; no third-party AI API keys or external AI services.

------------------------------------------------------------------------

## 1. Product summary

Build a highly customizable, privacy-first iPhone fitness companion that
combines four core areas:

1.  **Gym** --- workout routines, exercise logging, strength
    progression, history and analytics.
2.  **Health** --- Apple Health/HealthKit integration, activity, sleep
    and recovery context where available.
3.  **Food & Nutrition** --- food logs, calories, macros, meals, water
    and nutrition trends.
4.  **AI features** --- on-device coaching and summaries using Apple's
    Foundation Models framework where supported, plus Apple's Image
    Playground framework for supported image-generation workflows.

The app is for one person, not a public multi-user product. Optimize for
a deeply personalized experience, fast daily logging, local-first
storage, excellent iOS interaction patterns, and user control over every
target and reminder.

### Product principle

**Reliable data first; AI explains and assists, but does not invent the
data.**

Calculations such as workout volume, calorie totals, macro totals,
streaks, trends and target adherence must be implemented
deterministically in Swift. Use AI for summarization, natural-language
explanations, structured suggestions and supported creative/image
workflows.

------------------------------------------------------------------------

## 2. Goals and non-goals

### Goals

-   Native iOS experience built with SwiftUI.
-   Work without an account or backend for the initial release.
-   Store personal records locally and support backup/export options.
-   Read available health and fitness information through HealthKit with
    explicit permission.
-   Allow manual logging when HealthKit data is absent.
-   Make Gym, Health, Nutrition and AI features work together without
    requiring all modules to be configured first.
-   Provide clear empty states for a new user.
-   Make routines, targets, dashboard widgets, reminders and tracking
    preferences editable.
-   Use Apple Foundation Models for suitable on-device AI tasks when the
    model is available.
-   Gracefully disable or substitute AI features when unsupported or
    unavailable.

### Non-goals for the initial release

-   Android, iPad, web or watchOS app.
-   Multi-user accounts, social feeds, leaderboards or community
    features.
-   Cloud backend, user authentication or server database.
-   Third-party AI APIs, API keys, cloud LLM providers or third-party
    image-generation services.
-   Medical diagnosis, treatment recommendations or claims that the app
    can diagnose health conditions.
-   Guaranteed prediction of future physique or body composition.
-   Automatic exercise recognition from camera footage.
-   Automatic calorie/macronutrient certainty from food images.
-   Full Apple Watch app. The iPhone app may read Apple Watch data
    already present in HealthKit if the user has a watch, but the app
    must not require one.

------------------------------------------------------------------------

## 3. Target platform and technical baseline

### Recommended stack

-   **Language:** Swift
-   **UI:** SwiftUI
-   **Persistence:** SwiftData for app-owned structured records; use
    file storage in the app's protected container for photos and
    generated images.
-   **Health integration:** HealthKit
-   **AI text and structured generation:** Foundation Models
    (`FoundationModels`) when supported.
-   **System image generation:** Image Playground (`ImagePlayground`)
    when supported. Do not assume it can produce realistic, anatomically
    faithful physique predictions.
-   **Charts:** Swift Charts
-   **Notifications:** UserNotifications
-   **Haptics:** Core Haptics or UIKit feedback generators where
    appropriate.
-   **Biometric app lock:** LocalAuthentication (optional).
-   **Image import/capture:** PhotosPicker and AVFoundation only where
    camera capture is required.
-   **Testing:** XCTest / Swift Testing, UI tests where practical.

### Compatibility rule

Do not assume the user's current beta OS is the minimum supported OS.
Before implementation, inspect the installed Xcode SDK and current Apple
documentation. Select a stable deployment target compatible with the
required APIs. Gate Foundation Models and Image Playground features with
runtime availability and capability checks. Do not make the entire app
depend on AI availability.

### Architecture

Use a modular, testable architecture. Suggested layers:

-   `App` --- app entry, navigation, dependency container.
-   `Core/DesignSystem` --- colors, typography, spacing, components,
    haptics.
-   `Core/Storage` --- SwiftData models, migrations, repositories, file
    storage.
-   `Core/HealthKit` --- authorization, queries, observers,
    normalization and sync status.
-   `Core/AI` --- capability checks, prompt templates, typed outputs,
    safety validation.
-   `Core/Notifications` --- reminder scheduling and permission
    handling.
-   `Features/Onboarding`
-   `Features/Home`
-   `Features/Gym`
-   `Features/Health`
-   `Features/Nutrition`
-   `Features/Progress`
-   `Features/AIChat`
-   `Features/Settings`

Keep business logic out of SwiftUI views. Use services and view
models/observable state objects. Use dependency injection so HealthKit
and AI services can be mocked in tests.

------------------------------------------------------------------------

## 4. Core navigation and information architecture

Recommended bottom tab bar:

1.  **Home**
2.  **Gym**
3.  **Nutrition**
4.  **Health**
5.  **AI Coach**

Settings is accessible from the Home header and the AI Coach screen.
Progress photos, measurement history and analytics can live inside
relevant modules instead of requiring additional top-level tabs.

### Global requirements

-   Native navigation, safe areas, Dynamic Type where practical,
    VoiceOver labels, adequate contrast and accessible tap targets.
-   Support dark appearance as the default visual direction; follow the
    system appearance or provide an explicit theme setting.
-   Consistent near-black/charcoal surfaces and restrained orange foreground
    accents. Background imagery uses soft neutral lighting without neon,
    colored glow, fire or flashy lighting effects.
    Centralize tokens; do not hardcode colors throughout views.
-   Haptics must be subtle and configurable.
-   Respect reduced motion and notification preferences.
-   Never show fake sample statistics as if they were the user's real
    data.

------------------------------------------------------------------------

## 5. First-launch onboarding

Onboarding should be short and must not force detailed setup.

### Screen 1 --- Welcome

-   App name/logo.
-   Short promise: "Your fitness, your data, your rules."
-   `Get Started` CTA.
-   If onboarding is already complete, open Home instead.

### Screen 2 --- Primary fitness goal

Exactly one primary goal: - Build muscle - Lose fat - Body
recomposition - Strength - Endurance - General fitness

Persist the selection. Allow changing it later in Settings. Do not
include secondary goals in this onboarding flow.

### Screen 3 --- Personal information

Fields: - Name - Age (or date of birth, choose one approach; age is
simplest for the initial version) - Gender (optional) - Height - Current
weight - Target weight (optional) - Unit preferences: kg/lb and cm or
ft/in - Profile image/avatar is optional and can be configured later in
Settings.

Validate sensible input ranges and allow editing. Avoid deriving health
claims from gender or other profile fields. Explain why any optional
field is requested.

### Finish onboarding

-   Save onboarding completion and profile data locally.
-   Navigate to Home.
-   Do **not** ask for workout schedule, nutrition details, notification
    permission or HealthKit permission during onboarding.

### After onboarding --- Apple Health connection prompt

On first Home entry, show a one-time, dismissible explainer: - Title:
"Connect Apple Health" - Explain that supported activity and health
metrics can be read with permission. - `Connect Apple Health` and
`Not Now`. - If dismissed, do not show a blocking popup repeatedly. Show
a small optional connection card in Home or Settings. - Actual access is
controlled by the HealthKit system permission sheet, per data type. Do
not claim that the app can tell whether a read permission was denied;
HealthKit deliberately limits that visibility. - Users can revisit
Settings to connect/configure later.

------------------------------------------------------------------------

## 6. Home dashboard

The Home screen must be useful on day one, before routines or health
data exist.

### Header

-   Greeting using the saved name.
-   Date/day.
-   Avatar/profile shortcut.
-   Settings shortcut.
-   Optional notification/reminder entry point.

### First section: Today's workout card

This is the first major Home card.

**If a routine has a workout scheduled today:** - Show workout name and
planned muscle groups. - Show exercise count and estimated duration if
configured. - CTA: `Start Workout`. - Secondary actions: `View Routine`,
`Edit Routine`.

**If today is a planned rest day:** - Show a clear `Rest Day` card. -
Optionally show a short recovery note; do not guilt the user.

**If a routine exists but today has no session:** - Show
rest/flexible-day state and an option to view the schedule.

**If no routine exists:** - Show "Plan your workouts" and explain that a
weekly routine can be created. - CTA: `Set Up Workout Routine` routes to
the routine builder. - Do not show an empty chart or fabricated workout.

**If today's workout is completed:** - Show completion status, duration,
exercises/sets completed and volume if available. - CTA to view workout
summary.

### Other Home sections

-   Daily activity summary using HealthKit values only when available;
    otherwise show a connect/log empty state.
-   Nutrition summary with logged calories/macros and targets if
    configured.
-   Water progress and quick-add action.
-   Quick actions: Log Workout, Log Meal, Add Water, Record Weight.
-   Setup checklist for unconfigured features (workout routine,
    nutrition targets, HealthKit).
-   Compact progress/consistency preview only after enough real data
    exists.
-   AI insight card only when AI is available and enough relevant data
    exists; otherwise show an optional `Try AI Coach` entry point.

### Home customization

Future-ready requirement: allow hiding/reordering widgets. In MVP, a
simple list of available widgets and on/off toggles in Settings is
sufficient.

------------------------------------------------------------------------

## 7. Gym module

### 7.1 Routine builder

-   Create, edit, duplicate, rename and delete routines.
-   Support templates: Push/Pull/Legs, Upper/Lower, Full Body, Bro Split
    and Custom. Templates are starting points, not restrictions.
-   Assign training days to weekdays.
-   Assign workout title and focus/muscle groups to each day.
-   Configure session duration target.
-   Add, remove, reorder and replace exercises.
-   Configure default sets, rep range, target load (optional), rest
    duration, and notes.
-   Allow warm-up and working sets.
-   Allow rest days and flexible/unassigned days.
-   Allow moving a session to another day without silently rewriting the
    whole routine.
-   Store routine version/history or at minimum preserve prior completed
    workout records when the routine is edited.

### 7.2 Exercise library

Each exercise may include: - Name and aliases. - Primary/secondary
muscle groups. - Equipment. - Movement pattern and compound/isolation
classification. - Instructions, cues and safety notes. - Exercise
variations/alternatives. - User-defined favorite flag. - User-defined
custom exercise. - Optional demonstration media only if legally and
technically available; do not block core functionality on media.

Include an interactive front/back human SVG muscle map for selecting
muscle groups. Use named SVG regions and accessible labels; selected
muscles must be highlighted with a clear selected state. Do not rely
only on color to indicate selection.

### 7.3 Active workout session

-   Start, pause, resume and finish.
-   Show current exercise, sets, reps, load, rest timer and notes.
-   Add/edit/delete sets.
-   Set types: warm-up, working, drop set; supersets can be a later
    enhancement.
-   Record weight, reps, RPE or RIR optionally.
-   Haptic cue when a rest timer completes, if enabled.
-   Skip or replace exercise.
-   Add an unplanned exercise.
-   Auto-save each change and recover an interrupted session.
-   Handle app backgrounding and force quit safely.
-   Finish flow displays completed exercises, sets, duration, total
    volume and new PRs where calculable.
-   User can mark a workout complete, skipped or abandoned; do not treat
    a skipped workout as completed.

### 7.4 Strength and progression

-   Exercise history.
-   Total volume: define for weighted resistance sets as `load × reps`,
    summed across qualifying sets. Keep bodyweight and duration-based
    exercises separately labeled where volume is not comparable.
-   Personal records: max load, rep record at a load, estimated 1RM only
    where a chosen formula is documented.
-   Track volume by workout, exercise, week and muscle group.
-   Show trends only when enough valid data exists.
-   Do not call a muscle group "weak" solely from a low number;
    comparisons depend on exercise choice and history.

### 7.5 Gym history and analytics

-   Calendar with planned/completed/skipped/rest states.
-   Weekly activity heatmap.
-   Workout streaks with clear rules.
-   Planned vs. completed sessions.
-   Exercise performance and strength charts.
-   Training frequency by muscle group.
-   Filters by date and exercise.
-   Export workout history as CSV/JSON.

### 7.6 Gym acceptance criteria

-   User can create a routine and see the correct planned session on
    Home for the current weekday.
-   Rest days never appear as missing workouts.
-   Every set is saved immediately.
-   Killing/reopening the app during a workout restores the active
    session.
-   Completed workouts remain historically accurate after a routine
    edit.
-   Calculated volume matches the sum of qualifying set load × reps.
-   All core workout logging works without Apple Intelligence.

------------------------------------------------------------------------

## 8. Health module and Apple Health / HealthKit

The app is iPhone-only and must not require Apple Watch. It may read
supported data recorded by iPhone or any other source already writing to
HealthKit.

### Potential read categories (only when available and authorized)

-   Step count.
-   Walking/running distance.
-   Active energy and resting energy.
-   Heart rate and resting heart rate.
-   Workouts, duration and workout type.
-   Sleep duration/stages when available.
-   Height and body mass.
-   Body fat percentage and other measurements if recorded.
-   Dietary energy, protein, carbohydrates, fat and water if compatible
    apps have written these values.
-   Cardio fitness/VO₂ max and HRV if available from a compatible
    source.

Do not promise every metric will exist. Availability depends on
hardware, data sources, user permissions and OS support.

### HealthKit implementation requirements

-   Add HealthKit capability and required purpose strings.
-   Check `HKHealthStore.isHealthDataAvailable()` before access.
-   Request authorization for specific data types when the user connects
    Apple Health, with clear pre-permission copy.
-   Keep read and write permissions separate; default to read-only until
    writing is explicitly needed.
-   Do not ask for all possible types at once if a staged request is
    more appropriate.
-   Handle no data, limited history, denied permissions and unavailable
    types gracefully.
-   HealthKit does not reliably tell the app whether read permission was
    denied; treat an empty result as "no accessible data" rather than
    asserting the user denied permission.
-   Avoid duplicate records when the user manually logs data also
    imported from HealthKit.
-   Preserve source/date metadata and avoid writing imported data back
    as if the app created it.
-   Offer `Connect Apple Health` from Settings at any time.
-   Provide clear status per data category where possible, without
    claiming hidden authorization knowledge.

### Health screens

-   Activity dashboard with daily and weekly trends.
-   Weight/body metrics history.
-   Sleep/recovery summary where available.
-   Heart-related trends only as informational metrics, not diagnosis.
-   Water tracking and hydration history.
-   Source labels for synced vs. manually entered data.
-   Manual fallback for data unavailable in HealthKit.

### Health acceptance criteria

-   App remains fully usable if HealthKit is unavailable or the user
    skips connection.
-   Every HealthKit query handles empty results and errors.
-   No diagnosis or treatment claim is generated.
-   Imported records retain timestamps and source information when
    available.
-   User can revoke permissions in iOS Settings and app remains stable.

------------------------------------------------------------------------

## 9. Food & Nutrition module

### Daily food logging

-   Meal categories: Breakfast, Lunch, Dinner, Snack, and custom.
-   Search existing foods and saved foods.
-   Manual food creation.
-   Serving size and unit.
-   Calories, protein, carbohydrates, fat, and optional
    fiber/sugar/micronutrients.
-   Save meals and recipes for reuse.
-   Edit/delete entries and preserve date/time.
-   Quick-add calories/macros if the user does not know exact foods.
-   Food photo may be attached as a private note in MVP; do not claim
    reliable AI nutrient recognition from photos unless explicitly
    supported and validated.

### Targets

-   Daily calorie target.
-   Protein, carbohydrate and fat targets.
-   Optional fiber/water targets.
-   Targets may be manually set or suggested using transparent
    deterministic formulas. Clearly label estimates and allow overrides.
-   Avoid prescribing aggressive weight-loss targets.
-   If targets are not set, allow logging without blocking the user.

### Daily and weekly summaries

-   Consumed vs. target.
-   Remaining amount only when a target exists.
-   Macro distribution.
-   Weekly adherence.
-   Most frequently logged meals.
-   Trends and data-quality caveats.

### Water

-   Custom daily goal.
-   Quick-add amounts.
-   Edit/delete entries.
-   Reminders configured separately.
-   Optional HealthKit read/write integration, with deduplication rules.

### Nutrition acceptance criteria

-   Totals match the sum of entries.
-   Editing/deleting an entry updates totals immediately.
-   Users can log foods without AI or internet.
-   Missing targets are represented as unset, not zero.
-   HealthKit-imported nutrition is not silently double-counted with
    app-entered foods.

------------------------------------------------------------------------

## 10. Body measurements and progress photos

-   Dated progress photo entries, including capture/log date and time.
-   Photo sources: camera or Photos picker.
-   Optional measurements: body fat %, waist, chest, arms, thighs, hips
    and neck.
-   Weight history and measurement charts.
-   Front/side/back photo labels.
-   Timeline and side-by-side comparison.
-   Private local storage by default.
-   Delete photo and associated metadata.
-   Do not include sensitive photos in AI prompts unless the user
    explicitly chooses an image feature and understands what will
    happen.
-   Avoid uploading photos; the initial app has no backend.
-   Generated images must be clearly labeled as AI-generated.

### Physique visualization constraint

Apple's Image Playground supports system-supported image generation
styles and workflows, but it is not a guaranteed photorealistic
body-composition simulator. Do not promise accurate 1/3/6/12/24-month
physique prediction using Apple Intelligence alone. If offered, label it
an illustrative creative visualization, confirm that the required
framework supports the target workflow on the device, and allow the user
to cancel. If unsupported, ship progress-photo comparison rather than
fabricating a predictive feature.

------------------------------------------------------------------------

## 11. Reminders and notifications

User-configurable reminders: 1. Water reminders by interval or scheduled
time. 2. Workout reminders by selected weekdays and times. 3. Meal
reminders. 4. Bedtime/wind-down reminders. 5. Weigh-in reminders: daily,
weekly or custom. 6. Progress photo reminders: daily, weekly or monthly.
7. Supplement reminders (optional). 8. Custom reminder title, schedule
and frequency. 9. Quiet hours. 10. Rest-day, cheat-meal and
skipped-workout tracking.

Requirements: - Ask for notification permission when the user configures
a reminder or after explaining its benefit, not immediately on first
launch. - Provide enable/disable and edit controls. - Avoid duplicate
notifications when a schedule changes. - Respect quiet hours where
technically possible. - Do not label a planned cheat meal as failure. -
Rest day is distinct from skipped workout. - Notifications are optional;
core features must work without them.

------------------------------------------------------------------------

## 12. AI features --- Apple-native only

### 12.1 AI capability strategy

Use Foundation Models for tasks it supports and only when
`SystemLanguageModel` reports availability. The model can change with OS
updates, so test prompts on each supported OS/model version.

**No external AI API keys or cloud AI providers in this phase.** Do not
create a backend to proxy a model.

### 12.2 Suitable initial AI use cases

-   Summarize a day/week from locally computed statistics.
-   Explain workout and nutrition trends.
-   Convert a user's natural-language note into a draft structured log
    for user confirmation.
-   Provide habit suggestions based on real data supplied by the app.
-   Answer general fitness questions with appropriate safety boundaries.
-   Generate a proposed workout/nutrition adjustment that the user
    reviews before applying.
-   Use guided/structured generation for typed suggestion objects where
    supported.
-   Use tool calling only for a small set of read-only app tools when
    necessary.

### 12.3 AI must not be the source of truth

-   Calculate metrics in Swift; pass results to the model.
-   Give the model only a compact, relevant summary, not the entire
    database.
-   Validate generated structured output before using it.
-   Never allow AI to silently modify routine, nutrition target,
    reminder, or HealthKit records.
-   Require user confirmation before applying any AI-proposed change.
-   Never fabricate HealthKit readings or logged foods.
-   Clearly distinguish measured data, estimates and AI-generated
    advice.

### 12.4 AI chat

-   Local chat history.
-   Suggested prompts such as "Summarize my week", "How is my workout
    consistency?" and "Help me plan next week".
-   Context selector/permissions for Gym, Nutrition, Health and profile
    data.
-   Clear conversation, delete individual conversations, and clear all
    AI history.
-   Show unavailable state when Foundation Models is unsupported,
    downloading, restricted or otherwise unavailable.
-   Provide a non-AI fallback: deterministic summaries and standard help
    text.

### 12.5 Prompting and context management

-   Version all system instructions and prompt templates.
-   Keep prompts concise.
-   Include only data relevant to the question.
-   Use `tokenCount(for:)`/context-size facilities where available to
    avoid context overflow.
-   Summarize older chat context locally rather than appending unlimited
    history.
-   Test prompt behavior after OS/model updates.
-   Log performance diagnostics without logging sensitive prompt
    contents by default.

### 12.6 AI safety boundaries

-   The app is for fitness/wellness, not medical diagnosis.
-   Do not diagnose conditions, interpret symptoms as a confirmed
    disease, recommend medication or advise ignoring medical care.
-   For concerning symptoms, advise the user to seek appropriate
    professional care.
-   For injuries or pain, recommend stopping the aggravating exercise
    and seeking qualified advice where appropriate.
-   Avoid extreme dieting, unsafe dehydration, dangerous supplement
    advice or overtraining encouragement.
-   Provide conservative, evidence-aligned general guidance and
    encourage professional advice for medical conditions.
-   Treat AI output as suggestions, not guaranteed outcomes.

### 12.7 Image understanding and image generation

-   Verify the exact capabilities of Foundation Models and Image
    Playground in the target SDK; do not infer app API availability from
    consumer Siri/Image Playground features.
-   Use Image Playground only for supported system image-generation
    workflows.
-   Do not claim it can reliably assess body fat, muscle mass, health
    status, or predict an anatomically accurate future physique.
-   If photo understanding is unavailable in the selected
    framework/device configuration, defer photo-based AI analysis.
-   Keep a non-AI photo timeline and before/after comparison available
    regardless.

### 12.8 AI acceptance criteria

-   The app functions when the model is unavailable.
-   Every AI response is cancellable and has loading/error states.
-   Structured output is validated.
-   AI cannot write user data without explicit confirmation.
-   No health metric is invented.
-   Tests cover unavailable model, generation failure, empty context,
    long context and unsafe requests.

------------------------------------------------------------------------

## 13. Settings and customization

Settings should include: - Profile name, age, optional gender, height,
weight and avatar. - Units: kg/lb, cm/ft-in. - Primary fitness goal. -
Workout routine management. - Nutrition targets and dietary
preferences. - Water/sleep/step goals. - Reminder schedules and quiet
hours. - Apple Health connection entry point and explanations. -
Dashboard widget visibility/order (MVP may support visibility only). -
Theme and haptic preferences. - AI coach preferences and data context
permissions. - Face ID app lock (optional). - Export data. - Delete
local data/photos/AI conversations. - App version and privacy
information.

Because this is a personal single-user app, avoid unnecessary sign-in,
onboarding funnels, subscription paywalls, social features or analytics
SDKs.

------------------------------------------------------------------------

## 14. Data model baseline

Use SwiftData models or equivalent. The following is a conceptual
schema; refine it to match the chosen OS SDK.

### UserProfile

-   id
-   name
-   age or dateOfBirth
-   gender (optional)
-   heightValue + heightUnit
-   currentWeightValue + weightUnit
-   targetWeightValue (optional)
-   primaryGoal
-   avatarType / avatarEmoji / localAvatarPath
-   createdAt / updatedAt

### WorkoutRoutine

-   id, name, isActive
-   createdAt, updatedAt
-   schedule entries

### RoutineDay

-   id, weekday or flexible schedule identifier
-   title
-   focusMuscleGroups
-   isRestDay
-   estimatedDurationMinutes
-   ordered exercise references

### Exercise

-   id, name, primaryMuscles, secondaryMuscles
-   equipment, movementType, instructions
-   isCustom, isFavorite

### RoutineExercise

-   id, exerciseID, orderIndex
-   targetSets, targetRepMin, targetRepMax
-   defaultRestSeconds
-   optional targetLoad and notes

### WorkoutSession

-   id, routineID (optional), plannedDate
-   startedAt, endedAt
-   status: planned/completed/skipped/abandoned/inProgress
-   notes, totalVolume (computed/cache only), duration

### WorkoutExerciseEntry

-   id, sessionID, exerciseID, orderIndex
-   notes

### WorkoutSet

-   id, workoutExerciseEntryID
-   setType
-   reps, loadValue, loadUnit
-   duration/distance for relevant exercises
-   optional RPE/RIR
-   completedAt

### FoodEntry

-   id, dateTime, mealType
-   foodName, servingAmount, servingUnit
-   calories, protein, carbs, fat
-   optional fiber/sugar/micronutrients
-   source: manual/HealthKit/imported
-   sourceIdentifier (optional), notes

### WaterEntry

-   id, dateTime, amount, unit, source

### DailyTarget

-   date or effectiveFrom
-   calories/protein/carbs/fat/water/steps/sleep targets (all optional)
-   source: manual/calculated

### BodyMeasurement

-   id, dateTime, metricType, value, unit, source

### ProgressPhoto

-   id, capturedAt, photoType (front/side/back/other)
-   localFilePath, notes
-   optional AI-generated flag and prompt metadata; never store
    sensitive prompt contents unnecessarily

### Reminder

-   id, type, title, schedule configuration, isEnabled
-   notification identifiers

### HealthSampleReference

-   dataType, sample UUID/source metadata where available, start/end
    dates, quantity/unit
-   avoid copying all HealthKit data into local storage unnecessarily;
    aggregate or cache only what the UI needs.

### AIConversation / AIMessage

-   id, createdAt, title
-   message role, text, timestamps
-   optional related feature/context references
-   support deletion
-   do not persist sensitive image content in conversation history by
    default.

### Data rules

-   Store dates with explicit calendar/time-zone handling.
-   Use decimal types appropriate for measurements; do not use
    display-formatted strings as the canonical value.
-   Keep units in data or normalize to a canonical unit and convert for
    display.
-   Preserve raw entries and calculate summaries from them.
-   Avoid duplicate HealthKit imports using stable identifiers/source
    metadata where possible.
-   Provide migrations for schema changes.

------------------------------------------------------------------------

## 15. Privacy and security

-   Local-first by default; no account or server required.
-   Store files inside the app's protected container.
-   Use platform data protection and avoid exposing private photos in
    logs.
-   Do not put secrets or API keys in the app. No third-party API keys
    should exist in this release.
-   Use least-privilege HealthKit permissions.
-   Explain why each permission is needed.
-   Do not assume an empty HealthKit query means permission was denied.
-   Ask before sending selected data or images to any system AI workflow
    that may involve processing beyond the device; disclose actual
    processing based on the API and OS version.
-   Support deleting AI chats, photos, and all local app data.
-   Optional Face ID lock through LocalAuthentication.
-   Do not include third-party analytics/advertising SDKs in MVP.
-   Keep diagnostic logs free of raw health data and photo paths where
    possible.

------------------------------------------------------------------------

## 16. Error, loading and empty states

Every module must support: - First-use/no-data state with a helpful next
action. - Loading state. - Permission not requested. - Data unavailable
on this device. - Empty query result. - HealthKit query error. - Model
unavailable. - Model generation failed/cancelled. - Notification
permission unavailable/denied. - Storage failure or missing photo
file. - Interrupted workout recovery.

Examples: - No routine: "Plan your workouts" +
`Set Up Workout Routine`. - No meals: "Start with your first meal" +
`Log Meal`. - No Health data: "Connect Apple Health or log manually". -
No progress history: "Your trends will appear as you log". - AI
unavailable: "On-device AI isn't available right now" +
deterministic/manual alternatives.

Never fill empty states with fake data unless clearly marked as demo
data in a separate development-only preview.

------------------------------------------------------------------------

## 17. Implementation phases for a coding agent

Build one phase at a time. At the end of each phase, compile, run tests
and provide a concise summary of files changed, behaviors implemented
and known issues. Do not start later phases until the current phase
meets acceptance criteria.

### Phase 0 --- Project foundation

Deliver: - SwiftUI project and app entry. - Design tokens, reusable
buttons/cards/fields. - Navigation shell and bottom tabs. - Dependency
container and service protocols. - SwiftData container and first
schema. - Basic unit-test target. - Runtime capability abstraction for
HealthKit/Foundation Models/Image Playground.

Done when: project builds and launches on simulator/device; navigation
works; no module depends on AI or HealthKit being available.

### Phase 1 --- Onboarding and profile

Deliver: - Welcome screen. - Single primary goal selection. - Personal
information form. - Validation and units. - Save locally and resume
after app termination. - First-run completion state.

Done when: user can finish onboarding once; relaunch opens Home; profile
can be edited in Settings; optional fields can be blank.

### Phase 2 --- Home dashboard and empty states

Deliver: - Header, Today's Workout card states, setup checklist, quick
actions. - Health and nutrition placeholders based on actual state. -
One-time HealthKit explainer popup with Connect / Not Now. - Settings
connection entry point. - No fake metrics.

Done when: all Home states render correctly with no data, routine, rest
day, completed workout and disconnected HealthKit.

### Phase 3 --- Gym routine builder

Deliver: - Exercise library seed data and custom exercises. -
Create/edit/duplicate/delete routine. - Schedule workout/rest days. -
Configure exercises, sets, reps, rest and order. - SVG muscle map with
front/back selection. - Routine reflected on Home.

Done when: weekday schedule is correct and changes persist.

### Phase 4 --- Workout execution and history

Deliver: - Start/pause/resume/finish session. - Set logging, rest timer,
haptics, notes and exercise replacement. - Autosave and
interrupted-session recovery. - Completed/skipped/abandoned states. -
Session summary and history.

Done when: no set is lost on normal app interruption and historical
sessions remain stable after routine edits.

### Phase 5 --- Gym analytics

Deliver: - Volume calculations. - PRs and exercise history. - Workout
calendar and heatmap. - Frequency, adherence and strength charts. -
Export.

Done when: calculations are unit-tested against known examples and empty
histories display correctly.

### Phase 6 --- Nutrition and hydration

Deliver: - Food search/local food catalogue and manual food creation. -
Meals and saved foods/recipes. - Daily calorie/macro totals and optional
targets. - Water logs and quick add. - Weekly trends and empty states.

Done when: totals update correctly after create/edit/delete and work
offline.

### Phase 7 --- HealthKit integration

Deliver: - Capability, purpose strings, authorization flow. - Read
supported iPhone/HealthKit data. - Normalize units, timestamps and
source metadata. - Activity/weight/sleep/workout views where data
exists. - Settings connection entry point. -
Empty/permission/unsupported/error handling. - Optional writes only if
the user explicitly enables the relevant feature.

Done when: app remains functional with no HealthKit permission and does
not double-count manual entries.

### Phase 8 --- Body measurements, photos and reminders

Deliver: - Capture/import photos, tag and timestamp. - Measurement logs
and charts. - Secure local photo storage and deletion. - Reminder
configuration, quiet hours and notification scheduling. - Rest/cheat
meal/skipped session labels.

Done when: photo records and reminders survive relaunch; changing a
reminder does not leave duplicate scheduled notifications.

### Phase 9 --- Apple-native AI

Deliver: - Foundation Models availability service. - AI chat and local
conversation history. - Daily/weekly summaries using deterministic
aggregates. - Habit and training suggestions. - Structured output
validation. - User-confirmed application of proposed changes. - Safe
unavailable/error fallback. - AI privacy controls and delete history. -
Optional Image Playground integration only if supported by the selected
SDK and device.

Done when: app functions without AI, AI never invents data as fact, and
it cannot silently modify records.

### Phase 10 --- Settings, polish and hardening

Deliver: - Complete settings and customization. - Optional Face ID
lock. - Data export/delete. - Accessibility pass. - Dark/light
appearance behavior. - Performance profiling. - Migration tests and UI
tests. - On-device validation on the actual iPhone.

Done when: critical flows are tested on a real device and no known
data-loss bugs remain.

------------------------------------------------------------------------

## 18. Testing strategy

### Unit tests

-   Unit conversion.
-   Calorie and macro aggregation.
-   Workout volume and PR calculation.
-   Streak rules and calendar boundaries.
-   Routine weekday mapping.
-   Reminder schedule generation.
-   HealthKit sample normalization/deduplication.
-   AI structured-output validation and safety filtering.

### UI tests

-   First launch → onboarding → Home.
-   Skip Apple Health → use app normally.
-   Connect HealthKit → handle permissions and no data.
-   Create routine → verify Home card.
-   Start workout → log sets → terminate/reopen → resume.
-   Complete workout → verify history and volume.
-   Log/edit/delete meal → verify totals.
-   Add water → verify daily total.
-   Add/delete progress photo.
-   Configure/edit/disable reminder.
-   Foundation Models unavailable → fallback UI.
-   Delete local data and confirm removal.

### Manual device tests

-   Real iPhone, not simulator alone, for HealthKit and on-device AI
    behavior.
-   Low storage.
-   Airplane mode.
-   App background/force quit during workout.
-   Permission changes in Settings.
-   OS/model update.
-   Different calendar/time-zone settings.
-   Dynamic Type and VoiceOver.
-   Notification denied.

------------------------------------------------------------------------

## 19. Definition of done for every phase

A phase is not complete until: 1. The project builds without errors. 2.
Acceptance criteria pass. 3. Unit tests are added for calculations and
business logic. 4. Empty, loading and error states are handled. 5. Data
persists across app relaunch. 6. No unrelated features regress. 7. UI
uses shared design tokens. 8. The coding agent summarizes
implementation, tests, files changed and remaining issues. 9. No
secrets, fake user data or third-party AI integrations are introduced.
10. The code is modular enough for the next phase.

### Coding-agent operating instructions

-   Inspect the repository before editing; do not overwrite existing
    work blindly.
-   If starting from an empty repository, create the native SwiftUI
    project first.
-   Implement only the requested phase, not the entire roadmap in one
    pass.
-   Prefer native Apple frameworks and avoid dependencies unless
    justified.
-   Verify API availability in the installed SDK and Apple
    documentation.
-   Do not invent APIs or assume beta framework signatures.
-   Keep business logic testable and views small.
-   Ask a question only when a genuinely blocking product decision
    cannot be resolved from this PRD; otherwise use the defaults above
    and document assumptions.
-   Never claim a feature works without building/testing it.
-   At the end of each phase, report: summary, changed files, tests
    run/results, limitations, and exact next phase.

------------------------------------------------------------------------

## 20. Open decisions to confirm before release

These can use sensible defaults during early implementation: - Final app
name and bundle identifier. - Exact minimum iOS deployment target after
SDK/API inspection. - Whether age or date of birth is stored (prefer age
for MVP and avoid retaining DOB unless needed). - Whether the app should
write any manually logged data back to HealthKit (default: read-only
until explicitly enabled). - Whether app lock is enabled (default:
optional). - Whether generated images are stored indefinitely (default:
user-controlled and deletable). - Whether future iCloud backup/sync is
desired (not in MVP). - Whether AI chat is retained indefinitely
(default: local, user-deletable).

------------------------------------------------------------------------

## 21. Official Apple documentation references

Use current documentation for implementation details because API
availability and signatures can change across OS and SDK releases:

-   Foundation Models:
    https://developer.apple.com/documentation/FoundationModels
-   Foundation Models context-window management:
    https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
-   HealthKit authorization:
    https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
-   HealthKit configuration:
    https://developer.apple.com/documentation/xcode/configuring-healthkit-access
-   HealthKit privacy:
    https://developer.apple.com/documentation/healthkit/protecting-user-privacy
-   Image Playground:
    https://developer.apple.com/documentation/imageplayground
-   SwiftUI: https://developer.apple.com/documentation/swiftui
-   SwiftData: https://developer.apple.com/documentation/swiftdata
-   UserNotifications:
    https://developer.apple.com/documentation/usernotifications
-   LocalAuthentication:
    https://developer.apple.com/documentation/localauthentication

**Important product constraint:** "Apple Intelligence only" means no
external AI provider in the initial release. It does not mean every
Apple Intelligence capability is exposed through a developer API, works
on every device, or is suitable for every task. Runtime-check
capabilities and keep non-AI alternatives available.

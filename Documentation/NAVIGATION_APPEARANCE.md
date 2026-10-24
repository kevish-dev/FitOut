# Navigation and appearance

Open Home → Settings → Profile → Edit profile & navigation. The App navigation
section selects Top-right menu or Bottom bar. Appearance selects System, Light
or Dark. Both apply immediately, without saving or discarding personal profile
edits. Save continues to save the editable profile fields separately.

The existing top-right menu remains the default. Both layouts use the same five
destinations: Home, Gym, Nutrition, Health and AI Coach. The reference-inspired
bottom layout groups the first four in a floating glass capsule and places AI
Coach in a separate circular control. It uses real app destinations; there is no
placeholder feed, camera or scanner action. Selection, deep links and current
workout routing retain their existing destination indices.

Bottom navigation reserves safe-area space for scrolling content, stays available
on pushed pages, and hides while a keyboard is visible. Presented sheets retain
their own navigation. The top-right layout closes on destination/layout changes;
Home, Gym, Nutrition and Coach reserve header space only when that layout needs
it. The profile Save action reserves space beside the corner menu. Switching
layout does not change the current tab or dismiss the profile editor.
Tapping the already selected destination returns to that section's root, so
Home remains a working way out of Profile and Settings.

Navigation style is stored in the container's UserDefaults. Unknown/missing
values fall back to the existing top-right layout. Appearance uses the existing
SwiftData PreferencesRepository and preserves haptics preferences. Failed writes
leave the previous appearance selected and show the error. Historical model
schemas are unchanged.

The app-level forced dark overrides were removed, including Info.plist and
project-generation settings. Saved appearance controls the root view and the
separate floating-workout window. System follows iOS; the existing default remains
Dark. Labels, surfaces, strokes and secondary text use adaptive semantic colors.
Light appearance uses pale neutral surfaces and a darker orange action accent.
Dark photographic cards keep white text; page backdrops receive a light neutral
wash in Light mode. Onboarding, routine sheets, exercise browsing, workout
logging, nutrition, hydration and coach screens inherit the chosen appearance.

Navigation has accessible destination names and selection traits. Larger
accessibility text sizes use icons with VoiceOver labels rather than cramped
bottom labels. Reduced Motion and Reduce Transparency follow the shared controls.
Typography and the subdued photography policy remain consistent with the app.

Regression sources cover style persistence, fallback from unknown layouts,
appearance persistence while retaining haptics, failed appearance writes, the five
destination mappings, and adaptive foreground/background contrast.
UI-test source also covers changing layouts, relaunch persistence, routing and
returning Home from Profile. Generic-iOS unsigned `build-for-testing` compiles
the app, widgets and test targets. No tests,
app, simulator or device were launched. Device verification remains necessary
for keyboard transitions, glass rendering, modal layouts and system theme changes.

# Navigation and appearance

Home → Settings → Edit profile & navigation selects Top-right menu or Bottom
bar, and System, Light or Dark appearance. Changes apply immediately and persist
independently of unsaved profile fields. Top-right remains the default.

Both layouts use Home, Gym, Nutrition, Health and AI Coach. Bottom navigation is
a native SwiftUI TabView, with a NavigationStack per destination. On iOS 26 and
later, the system draws and animates its Liquid Glass tab bar. There is no custom
capsule, extra outer stroke, separate Coach circle or manually positioned bottom
overlay. Older iOS versions use their native tab bar. System safe-area placement
keeps scrollable content and pinned buttons above the bar. The bar stays expanded
while scrolling and hides while typing; Coach's composer follows the keyboard
through its own safeAreaInset. Sheets keep their own navigation.

Switching tabs preserves each section's navigation stack. Reselecting a section
returns to its root. Changing navigation style keeps the selected section and
profile editor in place. The top-right menu closes on selection or layout changes;
its adjacent controls share a GlassEffectContainer on iOS 26+. Pages reserve header
space only when the corner menu is enabled.

Native custom glass uses the system's regular, interactive material, without an
extra fixed stroke or opaque tint over the effect. Reduce Transparency uses a solid
accessible surface. Older systems use the existing material fallback. See Apple's
[Liquid Glass overview](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
and [custom glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

Navigation style uses the container's UserDefaults; invalid values fall back to
the top-right menu. Appearance uses the existing PreferencesRepository, preserving
haptics preferences. Failed writes keep the previous appearance and show the error.
Saved appearance controls the app, floating workout control and workout sheet.
System follows iOS; the existing initial appearance is Dark. Semantic colors keep
labels and surfaces adaptive, while photographic cards retain white text.

Regression unit tests cover saved preferences, invalid values, failed writes,
destination mappings, adaptive contrast and floating-control geometry around tab
bars, action docks and keyboards. UI-test source checks native tab routing and
Coach composer clearance. It is compiled but not run as interactive UI automation.
Physical-device checks remain necessary for glass appearance and touch/keyboard
transitions.

# FitOut

Native SwiftUI onboarding for **iPhone 17**, built from the five supplied black-and-orange references. Portrait, dark appearance, bundled Orbitron/Rajdhani fonts, and an offline hero photograph. No web view or third-party runtime dependencies.

## Run

Open `FitOut.xcodeproj`, select the **FitOut** scheme and **iPhone 17** destination, then press **⌘R**. To run on a physical iPhone, select your development team in Signing & Capabilities. The checked-in Xcode project is ready to use; XcodeGen is only needed if editing `project.yml`.

## Implemented

- Welcome screen with a real, accessible Get Started button.
- Name validation, 60 emoji avatars across four pages, and native Photos picker with square image resizing.
- Gender selection and snapping age wheel (13–100).
- Independent current/target weights, scrolling ruler, and kg/lb units. Canonical values stay in kilograms to avoid conversion drift.
- Eight fitness goals with multiple selections, empty-selection validation, and a draggable finish control with a VoiceOver action.
- Saved profile summary, edit flow, and native sharing.
- Draft and completed profiles persist locally with UserDefaults; no account or network connection is needed.

The screenshots cover onboarding. Completion opens the saved profile summary; workout logging, cloud sync, and a training dashboard are outside this implementation.

## Tests

Press **⌘U** with iPhone 17 selected. `FitOutTests` covers required fields, age and weight bounds, independent weight values, unit conversion, profile serialization, relaunch persistence, completion, editing, corrupt storage recovery, and step bounds.

The same tests can run on macOS with `swift test` through the included `Package.swift`.

## Source map

- `FitOut/Views/`: five onboarding screens, shared controls, and completion summary.
- `FitOut/Models/`: profile types and persistent state.
- `FitOut/Resources/`: bundled image, app icon, fonts, and font licenses.
- `project.yml`: XcodeGen project source.
- `Tools/GenerateIcon.swift`: native vector wordmark icon generator.

The hero photo was prepared with image generation using the supplied welcome image to remove baked-in interface text. The other screens are native SwiftUI components. The app uses the actual iPhone status bar and home indicator, rather than drawing mock device chrome. Orbitron and Rajdhani are distributed under their bundled SIL Open Font Licenses.

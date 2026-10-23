# FitOut typography

Use the bundled Orbitron and Inter fonts through `FitTheme` in `FitOut/Views/DesignSystem.swift`. The reference screenshot establishes a wide geometric headline, small uppercase accent copy, and restrained interface text. A raster screenshot cannot reliably identify an exact font file, so the app uses its existing Orbitron display family and bundled Inter interface family.

| Role | Font | Typical size |
| --- | --- | --- |
| Hero | Orbitron ExtraBold | 30–36 pt |
| Screen title | Orbitron ExtraBold | 22–30 pt |
| Section heading | Inter SemiBold | 17–20 pt |
| Body | Inter Regular | 14–16 pt |
| Button | Inter SemiBold | 15–17 pt |
| Metadata | Inter Medium | 11–13 pt |
| Main metric | Orbitron Bold | 32–48 pt, scaled down for compact cards |

Use the semantic `FitTheme` font functions instead of adding new system-font sizes to app copy. Keep SF Symbols and emoji in the system font so their glyphs render correctly. The root view supplies Inter for controls and text that do not set a more specific font; navigation titles use Orbitron.

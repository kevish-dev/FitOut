# Subtle background imagery

Current visual direction: matte charcoal backgrounds, soft neutral lighting, natural subdued skin tones and graphite equipment. Preserve readable subject silhouettes. Orange belongs to small foreground controls and state indicators. Backgrounds must not use neon tubes, fire, sparks, bright colored rims, halos or glossy light trails. Glass surfaces stay neutral; functional health-chart colors remain meaningful.

The supplied IMG_5675.HEIC was converted to a temporary PNG and inspected as a lighting reference. Layout, fonts, workout behavior, scrolling and navigation remain intact. Replacements use existing asset keys, covering every consumer automatically. The streak uses a faint neutral system flame outline instead of its glowing bitmap. Selection and slider shadows, warm surface washes and orange glass tint were removed.

## Assets and final edit prompts

Tool: built-in `image_gen` (edit mode), `transparent_background: false`. All three edit targets were inspected before editing. The generated source files remain under `.codex/generated_images`; the final selected assets were copied into the project. The user explicitly requested replacing the bright background treatment.

### Home athlete

Saved project asset: `/Users/kevishsewliya/Downloads/VS_Stuff/FitOut/FitOut/Resources/Assets.xcassets/HomeAthlete.imageset/home-athlete.png`

Final prompt:

> Edit intent: lighting-weather and precise-object-edit. The FIRST image is the EDIT TARGET, the full-body male athlete performing a high kick. The SECOND image is only a STYLE REFERENCE for its soft charcoal and natural muted lighting, NOT for its UI or cropping. Create a production background photo asset for a dark fitness mobile app, tall portrait at the same approximately 1:2.16 aspect ratio as the edit target. Preserve the first image's male athlete, recognizable face, black clothing, gloves, entire kicking pose and body proportions, full raised boot at left and standing boot below; keep generous empty dark space above his head. Completely REMOVE all fire, orange sparks, glowing energy trails, neon outlines, colored rim lighting, spotlight beam, smoke effects and bright glossy floor reflections. Replace with a quiet matte charcoal studio backdrop and very subtle dark floor. Use ONLY soft diffused neutral lighting to gently reveal the body and clothing, with natural subdued skin color and soft low-contrast shadows. The background and floor should be dark neutral gray, no colored lighting at all. Subject visible and well defined rather than blacked out, no glistening high-contrast highlights. Calm photographic editorial realism. No text, UI, logos, phone frame, new props, new people, flames or artificial glow.

### Gym / opening athlete

Saved project asset: `/Users/kevishsewliya/Downloads/VS_Stuff/FitOut/FitOut/Resources/Assets.xcassets/FitnessHero.imageset/fitness-hero.png`

Final prompt:

> Edit intent: lighting-weather and precise-object-edit. The FIRST image is the EDIT TARGET: a man in a black tank top holding a barbell. The SECOND image is only a STYLE REFERENCE for its quiet matte charcoal photographic treatment, NOT for its UI or pose. Create a production fitness app background asset, tall portrait at the same approximately 1:2 aspect ratio as the first image. Preserve the first image's athlete identity, black clothing, barbell, stance, body proportions and composition. Keep full barbell and head, with useful empty space in upper left. REMOVE every orange/red light bar and neon tube, all colored rim lighting, orange glowing reflections, harsh hotspots, flare and bright light sources. Replace background with a charcoal gym with only very subdued out-of-focus neutral dark equipment silhouettes. Soft diffused neutral ambient studio lighting on athlete, natural low-saturation skin, matte fabric and weights. No oily shiny skin highlights, no sharp bright rims. Deep charcoal gray background, readable subject with gentle tonal contrast, absolutely no colored or neon lighting. Match the second image's restrained understated mood. No text, interface, phone frame, logos, new people, flames or visual effects.

### Routine and workout equipment

Saved project asset: `/Users/kevishsewliya/Downloads/VS_Stuff/FitOut/FitOut/Resources/Assets.xcassets/RoutineEquipment.imageset/routine-equipment.png`

Final prompt:

> Edit intent: lighting-weather and precise-object-edit. Edit the supplied production fitness app graphic, preserving the exact dumbbell and stacked weight plates composition, geometry, perspective, texture and landscape aspect ratio. Remove ALL orange/amber rim lighting, the orange halo, colored background light and reflective orange glow. Show matte dark charcoal rubber weights, restrained brushed neutral steel with soft highlights, and a uniform near-black charcoal background. Only gentle diffuse neutral lighting; no bright hotspot, no light beams, no neon, no luminous outline. Keep enough natural contrast to read the dumbbell at small UI sizes. Premium quiet product photograph consistent with a subtle dark gray fitness app. No text, logos, phone mockup, new objects, graphics or interface.

## Verification

The replacement PNGs were visually inspected and their dimensions checked. Generic-iOS unsigned `build-for-testing` compiles the app, widgets and test targets. Swift syntax, project plist and diff checks supplement that build. No app, simulator, device or tests are launched. In-app visual verification remains with the project owner.


# Routine editor visual redesign

The attached editor screenshot is the starting point for this redesign. The
Schedule, Workouts and Review flow, draft recovery, validation and saved data
remain in the existing editor. No new workout rules or persistence fields are
introduced.

- Stage controls use icons, a moving selection surface, pressed feedback and
  persistent placement above the scrolling content. Changing stages still
  returns the content to the top.
- Schedule uses a product illustration, counts of actual planned days/exercises/
  sets, circular training-day controls, a compact other-day menu and a labeled
  start-date disclosure. Counts describe the plan, not completed activity.
- Workouts uses a day rail with workout/rest/open symbols, visual day-type
  controls, labeled name input and an illustrated add-exercise state. Rest and
  open days have quiet native vector graphics.
- Exercise cards show larger uncropped system illustrations, muscle names and
  actual set targets. Mixed rep ranges and timed targets are identified rather
  than reduced to a misleading shared value. The set editor has numbered set
  cards, focused numeric fields and 30/60/90/120-second default-rest shortcuts.
  Per-set rest overrides keep their existing behavior.
- Review shows real weekly totals and illustrated daily cards. Each card still
  opens its corresponding day for editing. Template choices also show a small
  seven-day training pattern from their actual schedules.
- Typography stays Orbitron/Inter with the shared 20 pt page and 16 pt card
  insets. Glass uses the existing iOS 26, earlier-iOS and Reduce Transparency
  paths. Reduced Motion removes press scaling and stage/selection animation.
  Accessibility text sizes stack stage controls, daily summaries, metrics, rest
  shortcuts and numeric fields where appropriate.
- While the keyboard is visible, Done and the primary action share one aligned
  footer row. There is no separate floating keyboard-toolbar button. Helper
  text is hidden while typing to leave more room for the focused input; large
  accessibility sizes stack the actions. The footer shares the content's width
  limit and page insets. Advancing dismisses the keyboard first.

## Generated graphic

Tool: built-in `image_gen` tool, with `transparent_background: true`.

Project asset:
`FitOut/Resources/Assets.xcassets/RoutineEquipment.imageset/routine-equipment.png`

Asset key: `RoutineEquipment`. The original generated PNG is copied unchanged
into the project; the source under `.codex/generated_images` is retained. The
graphic is decorative and hidden from VoiceOver. Existing exercise illustrations
remain associated with their exact exercise variants.

Final generation prompt:

> Use case: product-mockup. Asset type: a small premium 3D illustration used inside a native iOS fitness routine editor. Create one isolated compact still life of a matte graphite adjustable dumbbell resting diagonally beside two stacked black weight plates. Three-quarter perspective with a polished steel knurled handle, tactile rubber surfaces and a restrained warm orange edge light (#FF4D00); soft neutral studio fill makes the equipment readable on dark charcoal UI. The equipment should occupy most of the image with comfortable clear space around every edge. Landscape composition about 3:2, no cropping of equipment. High-end realistic 3D product rendering, crisp silhouette, quiet lighting, no neon glow, fire or smoke. Actual transparent background. No people, no text, no lettering, no numbers, no logos, no watermark, no UI, no frame.

## Verification

Swift syntax, project validation, diff checks and an unsigned generic-iOS
`build-for-testing` compile the app, widget extension and test targets. Existing
UI-test source uses the new stage-button identifiers. The app and tests are not
launched; device interaction and visual inspection remain with the project
owner.

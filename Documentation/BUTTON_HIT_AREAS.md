# Full button hit areas

Manage sets now puts its glass and full-width, 48-point frame inside its button
label. FitPlainButtonStyle supplies a rectangular interaction content shape for
the whole laid-out label, including transparent spacing. It delegates activation
to a native plain Button, retaining the role and standard disabled, accessibility,
repeat and press behavior. It adds no tap gesture or transparent overlay.

All app uses of plain styling now use `.buttonStyle(.fitPlain)`; the one raw plain
style lives inside that shared implementation. The two animated routine button
styles also set interaction shapes. This covers custom controls/cards in onboarding,
Home, Gym, Nutrition, Coach, profile, navigation, floating workout controls and
workout setup/session/summary screens.

Auxiliary timer, previous-input, note, skip, library/filter and nutrition actions
put their padded touch frames inside their labels. Main custom actions retain
their existing dimensions. Undersized nutrition actions and favorite controls use
44-point targets. Saved-meal labels fill the available row. Exercise image labels
include their full framed/letterboxed region. Rows with independent actions retain
separate buttons; passive section containers do not gain an action. Sliders and
number-wheel gestures are unchanged.

For future custom controls, put visual padding, sizing and background inside the
Button/NavigationLink label, then apply the shared style to the control. A frame
outside a Button does not enlarge that Button's label target. Avoid adding an
onTapGesture to work around hit testing: it can bypass disabled state and compete
with scrolling or child controls. Native toolbar, menu, form and tab controls keep
their platform styles.

Verification: Swift parsing, whitespace checks and the unsigned iPhone
build-for-testing compile app, widget and test targets. No interactive UI tests
were run. The owner should check Manage sets by tapping its empty left/right
areas, plus quick-workout setup, exercise selection, navigation icons and floating
workout controls on iPhone. Check that disabled actions remain inactive and that
scrolling, number wheels and slide-to-continue still work normally.

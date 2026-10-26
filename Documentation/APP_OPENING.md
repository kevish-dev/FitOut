# App opening

Each new app process shows the existing FO logo on a quiet, near-black surface.
A slanted reveal follows the F's forward angle, the mark settles from 94% to full
size, and the FitOut wordmark appears. The reveal takes 680 ms; after a brief
hold the surface fades out over 180 ms (about one second overall). There are no
loops, particles, audio, haptics, new image assets, or runtime dependencies.
The original logo is reused; its dark outer padding is feathered with a mask.

The system launch screen uses the same named background color and remains
static. SwiftUI owns the animation after launch. Storage opens independently
of the animation. Home/onboarding mount when the intro completes, so their
permission explainers and session presentations do not appear over the logo.
Slow startup can show the existing progress state after the intro; a storage
error immediately exposes the preserved-data error and Retry action.

Tapping skips the opening; VoiceOver has a named Skip opening action and escape
action. Reduce Motion shows the complete logo and wordmark without a sweep or
scaling, then crossfades after 150 ms. Backgrounding or a valid widget deep link
ends the intro immediately. Returning from background, moving between tabs,
retrying storage, and restarting onboarding do not replay it. SwiftUI cancels
the bounded task when the opening is removed.

Validation: unsigned iPhone build-for-testing and static checks. No simulator
or device UI was launched; the owner should check the actual animation on an
iPhone, including Reduce Motion, saved light appearance, a widget launch, and
backgrounding during startup.

# AI Coach improvement plan

## Problem and scope

The existing implementation sends no app records, keeps only an in-memory chat,
and treats any nonempty model output as success. The reported greeting-only
behavior has not been reproduced with the physical-device model. This change
addresses those concrete weaknesses rather than promising a more capable model.

The coach remains Apple-native and on-device, with no accounts, API keys, cloud
fallback, backend, or AI access to write user records.

## Deliverables

1. **Useful answers:** compact task-specific instructions, structured answer / next
   step / optional question generation, enough output budget for a practical reply,
   validation and one repair for empty/greeting-only output. Fail honestly after
   the bounded retry. Stop, timeout, retry, partial replies and errors stay usable.
2. **Real context:** separate persisted, default-off switches for profile,
   training, nutrition and Health. Build small deterministic summaries from saved
   records. Select only relevant scopes for a question, preserve unknown/partial
   values, exclude future/invalid records and stale Health readings, omit private
   names/photos/notes, and never interpret record labels as instructions.
3. **Continuity and privacy:** protected local conversation storage, new/select/
   delete conversations, clear all history, and recovery of interrupted replies.
   Revoking a context permission excludes old shared context from future model
   requests, including after relaunch. Storage failures preserve the existing file
   and expose recovery rather than silently replacing it.
4. **Useful without AI:** a clearly labelled calculated summary of permitted app
   records, available even on an unsupported phone. This is not a simulated AI
   response. General AI chat remains unavailable when the model is unavailable.
5. **Focused UI:** preserve FitOut fonts, appearance, spacing, native sheets,
   keyboard clearance, text selection, and accessible controls. Add clear context,
   conversation and summary actions without introducing another navigation tab.

## Acceptance and validation

- Exercise technique, workout planning and meal questions ask for concrete answers,
  not introductions. Follow-ups retain bounded complete exchanges.
- Repeated greetings cannot be accepted as a finished substantive answer.
- Summaries agree with Workout/Nutrition/Health source calculations and do not turn
  missing readings or unlogged food into measured zeros.
- No context switch grants another scope. Revocation and conversation switching
  cannot leak a previous permission state back into a prompt.
- Relaunch preserves messages; interrupted output is labelled and retryable.
- Stop/timeout/delete cannot append a late reply. Failed disk reads cannot overwrite
  old conversations. Failed writes are visible and retryable.
- Unit tests cover aggregation, permissions, prompt bounds, output quality,
  cancellation, retries, persistence, deletion and storage failures.
- Build the iPhone app and run unit tests. The owner validates actual Foundation
  Models usefulness, latency, languages, safety and keyboard/appearance on-device.

## Deliberate boundaries

No automatic routine edits, nutrition prescriptions, inferred injuries, food-photo
recognition or invented measurements. Proposed plans are chat suggestions; saving
them still uses the existing routine or food editor. Apple Intelligence availability
and answer quality depend on the physical device and model. Capability checks,
typed generation and token counting follow the installed SDK and
[Apple's Foundation Models documentation](https://developer.apple.com/documentation/foundationmodels/languagemodelsession).

## Implementation checkpoint

All five deliverables above are implemented. The full 231-test suite passed with
zero failures; 26 tests cover coach behavior. The unsigned iPhone build passed.
Physical-device model quality/safety/latency and visual accessibility validation
remain owner QA. No assertion is made that the original greeting-only behavior
was reproduced on the real model, or that typed generation guarantees correctness.

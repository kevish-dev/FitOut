# AI Coach

The coach uses Apple's Foundation Models on supported iPhones with iOS 26+,
Apple Intelligence enabled and the model available. There is no cloud fallback,
external AI key, backend, simulated AI response, or AI write access to app records.
The implementation and acceptance scope are recorded in [AI_COACH_PLAN.md](AI_COACH_PLAN.md).

## Useful replies

Instructions version 2 request a direct answer, specific exercise/food steps,
reasonable stated assumptions and at most one important clarifying question.
Question-specific task instructions distinguish training plans/technique,
nutrition, wellness readings and summaries. Shipped exercise definitions supply
up to two name-matched technique references; this lookup never reads custom
exercise names or private notes. It works without granting personal-data access.

Guided generation produces answer, next step and optional-question strings. These
are rendered as ordinary paragraphs, not raw JSON. The response allowance is
768 tokens, with a compact prompt and up to three complete exchanges bounded to
3,000 characters. At iOS 26.4+, token counting reserves schema/output capacity
and removes older pairs when necessary. Earlier OS versions retain character
bounds and make one history-free retry on a context-overflow error.

Empty, greeting-only answers to substantive questions and obvious claims that the
coach saved/edited user records fail validation. One fresh repair attempt asks
for a direct answer to the original question; repeated poor output fails visibly
with Retry. This is a narrow quality guard, not a claim of semantic or medical
verification. The model's actual usefulness, language behavior and safety need
physical-device evaluation after OS/model changes.

Replies stream, support Stop and Retry, and time out after 60 seconds. Switching
pages, backgrounding, revoking context or deleting a chat cancels generation.
Request IDs prevent cancelled/uncooperative callbacks from appending late text.
Retries reuse the saved question rather than duplicating it. Old generation
errors and the iOS 27 error types map to actionable unavailable/language/context/
refusal/timeout states. SDK beta behavior still requires physical-device checks.

## Data context and calculated summaries

All personal-context switches default off and persist locally:

- **Profile:** goal, height and current weight; optional target weight for adults.
  Name, avatar and gender are excluded. Preferred units and under-18/adult status
  always guide answer formatting and safety and are disclosed in the composer.
- **Training:** current saved schedule, this calendar week's valid completed
  sessions/sets/active minutes/weighted volume, rest-protected streak and recent
  actual exercise performance. Draft plans and private notes are excluded.
- **Nutrition:** today's food values with missing/partial/estimated labels,
  configured targets, logged-day coverage, averages only after three complete
  logged days, and FitOut water. Unlogged days are not zero-calorie days. Burned
  energy is never treated as food intake or automatic calorie credit.
- **Health:** today's accessible steps, active energy, sleep and water, only with
  a current refresh timestamp and no query error. Missing/stale readings are
  unknown; no authorization denial, diagnosis or recovery score is inferred.

The sharing sheet previews the exact computed facts. Relevant facts are selected
for each question and bounded before JSON encoding as untrusted data. Future or
invalid workout/food/water records are excluded. Changing numeric facts preserves
follow-up continuity; changing permissions, goal, units or age group resets the
model's earlier context boundary. Each conversation saves that boundary, so
reopening another chat or relaunching cannot restore revoked context into a prompt.
Old messages remain visible until explicitly deleted.

**My records** produces an explicitly labelled, calculated summary from permitted
records without calling the model. It is available even when Apple Intelligence
is unavailable. It does not pretend to be AI advice. For general questions on
unsupported devices, the composer remains disabled and the actual reason is shown.

## Saved chats and privacy

`CoachPersisting` separates storage from orchestration. Production stores a
versioned JSON archive in Application Support/FitOut/Coach, using atomic writes
and iOS data protection until first unlock. Isolated disk test environments use
their own directory; in-memory containers use memory storage. No prompts or
personal context are written to diagnostic logs. No SwiftData schema is changed.

Questions and an interrupted-response marker save before generation; completed,
stopped and failed messages save at the corresponding transition. Relaunch turns
an interrupted reply into a stopped, retryable reply without automatically
regenerating it. New conversation retains older chats. History lets the user
select/delete a conversation, or confirm deletion of all chats and reset sharing.
Testing Start Over opens a fresh chat and preserves saved history.

Unreadable/newer archives are preserved and cannot be silently overwritten.
Sending is blocked until Retry succeeds or the user explicitly deletes all chats.
Write failures keep the transcript in memory, show a warning and offer retry.
Deleting coach history does not delete workout, nutrition, profile or Health data.

## Interface and validation

The coach retains FitOut typography, semantic appearance and 20 pt page margins.
Native sheets contain sharing and conversation history. The keyboard-safe composer
continues to report clearance for the floating workout control. Responses support
inline emphasis, text selection and Copy. Follow-up actions request more detail
or a simpler explanation. Calculated records and generated suggestions have
distinct labels; context labels describe what was shared, not proof of what the
model relied on.

Regression tests cover quality/repair bounds, complete history, private context
exclusion/revocation, real totals, missing/partial nutrition, stale/error Health,
library retrieval, prompt bounds, offline summaries, disk reopen, interrupted
reply recovery, corruption/version preservation, write retry, conversation
deletion and Stop/timeout races. Unsigned iPhone compilation and simulator unit
tests validate code paths, not real Foundation Models output or UI appearance.

On-device QA: ask for a 30-minute dumbbell session, squat cues, a pre-workout meal,
follow-up substitutions, a week summary with/without records, and unsupported/
unsafe requests. Check actual latency, streaming, cancellation, model availability,
relaunch, privacy revocation, large text, VoiceOver and both navigation styles.

Checkpoint: all 231 unit tests passed with zero failures, including 26 coach
tests. The unsigned iPhone app/widget/test build passed. No interactive simulator
or physical-device model evaluation was performed.

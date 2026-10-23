# AI Coach chat

AI Coach is reachable from the existing top-right navigation menu. It uses Apple's on-device Foundation Model on supported iPhones with iOS 26 or later, Apple Intelligence enabled, and the model ready. Other configurations show the actual availability reason and a disabled composer. There is no cloud fallback or fabricated chat response.

The coach is instructed to cover workouts, gym technique, cardio, mobility, recovery, food, and hydration, and to redirect unrelated requests. Instructions are versioned in `CoachContext.instructionVersion`. It receives preferred weight units and whether the user is under 18. The fitness goal is shared only when the user enables “Include my fitness goal”; this is off initially. It receives no name, body measurements, avatar, workout records, or HealthKit readings. It must ask for missing details instead of inventing them, and does not have tools to modify app data. Age-appropriate instructions exclude restrictive dieting and weight-loss targets for users under 18.

Replies stream into the conversation. A new request uses up to the three most recent complete exchanges, capped at 3,500 characters, in their native user/assistant roles. Failed or stopped replies are excluded. Inputs are limited to 1,200 characters, and only one reply runs at a time.

Changing the permitted profile context starts fresh model context without deleting the visible transcript. Turning off goal context therefore excludes earlier exchanges that may have included it from subsequent prompts.

The app container retains the conversation while moving between pages in the current app session. Chats are not written to disk and clear when the app process ends. New chat clears the transcript after confirmation. The testing Start Over action also clears it. Switching pages or leaving the active app stops generation; interrupted and failed replies can be retried without duplicating the question.

The UI shares FitOut's Orbitron/Inter typography, 20 pt page margins, dark surfaces, and orange accents. The keyboard moves the composer into view, and scrolling up to read older messages stops automatic scrolling until the user returns to the latest messages or sends another message.

import XCTest
@testable import FitOut

final class CoachTests: XCTestCase {
    func testHistoryContainsOnlyCompleteExchangesAndIsBounded() {
        var messages: [CoachMessage] = []
        for index in 0..<5 {
            messages.append(.init(role: .user, text: "Question \(index)"))
            messages.append(.init(role: .assistant, text: "Reply \(index)"))
        }
        messages.append(.init(role: .user, text: "Interrupted question"))
        messages.append(.init(role: .assistant, text: "Partial", state: .stopped))
        messages.append(.init(role: .user, text: "New question"))
        let history = CoachConversation.history(from: messages)
        XCTAssertEqual(history.count, 6)
        XCTAssertEqual(history.first?.text, "Question 2")
        XCTAssertEqual(history.last?.text, "Reply 4")
        let longPair: [CoachMessage] = [.init(role: .user, text: "Question"),
                                       .init(role: .assistant, text: String(repeating: "x", count: 4_000))]
        XCTAssertTrue(CoachConversation.history(from: longPair).isEmpty)
    }

    func testContextContainsScopeAndMinimalProfileInformation() {
        var profile = ProfileData()
        profile.name = "PRIVATE NAME"
        profile.currentWeightKG = 78.123
        profile.age = 16
        profile.primaryGoal = .strength
        let context = CoachContext(profile: profile)
        XCTAssertTrue(context.isUnder18)
        XCTAssertTrue(context.instructions.contains("For unrelated requests"))
        XCTAssertTrue(context.instructions.contains("Do not prescribe calorie deficits"))
        XCTAssertFalse(context.instructions.contains(profile.name))
        XCTAssertFalse(context.instructions.contains("78.123"))
        XCTAssertEqual(context.goal, "Not shared; ask if relevant")
        XCTAssertEqual(CoachContext(profile: profile, includeGoal: true).goal, "Strength")
    }

    @MainActor func testUnavailableAndInvalidMessagesNeverReachModel() async {
        let capability = CoachCapabilityStub(status: .unavailable(.deviceNotEligible))
        let responder = CoachResponderStub()
        let store = CoachStore(capabilities: capability, responder: responder)
        store.draft = "Help me plan a workout"
        store.send(context: CoachContext(profile: ProfileData()))
        await store.waitForResponse()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(responder.questions.count, 0)
        capability.status = .available
        store.refreshAvailability()
        store.draft = " \n "
        XCTAssertFalse(store.canSend)
        store.draft = String(repeating: "x", count: CoachConversation.maximumMessageLength + 1)
        store.send(context: CoachContext(profile: ProfileData()))
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(responder.questions.count, 0)
    }

    @MainActor func testFollowUpReceivesPreviousExchangeAndOnlyOneSendRuns() async {
        let responder = CoachResponderStub()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        let context = CoachContext(profile: ProfileData())
        store.draft = "Plan a workout"
        store.send(context: context)
        store.send(context: context)
        await store.waitForResponse()
        XCTAssertEqual(responder.questions, ["Plan a workout"])
        XCTAssertEqual(store.messages.last?.state, .complete)
        store.draft = "Can I use dumbbells instead?"
        store.send(context: context)
        await store.waitForResponse()
        XCTAssertEqual(responder.histories.last?.map(\.text), ["Plan a workout", "A focused fitness reply."])
        XCTAssertEqual(store.messages.count, 4)
        XCTAssertFalse(store.isResponding)
    }

    @MainActor func testRetryReusesQuestionAndExcludesFailedOutput() async {
        let responder = CoachResponderStub()
        responder.shouldFail = true
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        let context = CoachContext(profile: ProfileData())
        store.draft = "What can I eat before training?"
        store.send(context: context)
        await store.waitForResponse()
        XCTAssertTrue(store.canRetry)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.messages.last?.state, .failed)
        responder.shouldFail = false
        store.retry(context: context)
        await store.waitForResponse()
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(responder.histories.last?.count, 0)
        XCTAssertEqual(store.messages.last?.state, .complete)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor func testRemovingGoalContextExcludesEarlierExchanges() async {
        let responder = CoachResponderStub()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        var profile = ProfileData()
        profile.primaryGoal = .strength
        store.draft = "Help with my goal"
        store.send(context: CoachContext(profile: profile, includeGoal: true))
        await store.waitForResponse()
        store.draft = "What makes a balanced meal?"
        store.send(context: CoachContext(profile: profile))
        await store.waitForResponse()
        XCTAssertTrue(responder.histories[1].isEmpty)
        store.draft = "What about before a workout?"
        store.send(context: CoachContext(profile: profile))
        await store.waitForResponse()
        XCTAssertEqual(responder.histories[2].first?.text, "What makes a balanced meal?")
        XCTAssertFalse(responder.histories[2].contains { $0.text == "Help with my goal" })
    }

    @MainActor func testStoppingOrClearingQueuedSendCannotAppendLateReply() async {
        let responder = CoachResponderStub()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        let context = CoachContext(profile: ProfileData())
        store.draft = "Help with my squat"
        store.send(context: context)
        store.stop()
        XCTAssertEqual(store.messages.last?.state, .stopped)
        XCTAssertFalse(store.isResponding)
        XCTAssertTrue(store.canRetry)
        store.clear()
        await Task.yield()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(store.draft.isEmpty)
        XCTAssertEqual(responder.questions.count, 0)
        XCTAssertFalse(store.canRetry)
    }

    func testUsefulReplyValidationRejectsGreetingOnlyAndFalseWriteClaims() {
        for text in ["", "Hi", "Hello! How can I help you today?", "Hi! I'm here to help with your fitness and nutrition goals. What would you like to work on?", "I saved your routine for tomorrow."] {
            XCTAssertFalse(CoachReplyQuality.accepts(text, question: "Plan a 30-minute workout"), text)
        }
        XCTAssertTrue(CoachReplyQuality.accepts("Hi!", question: "Hi"))
        XCTAssertTrue(CoachReplyQuality.accepts("Use a load you can control for 8 reps, then rest for 90 seconds.", question: "How do I start?"))
        XCTAssertTrue(CoachReplyQuality.accepts("What equipment do you have available?", question: "Help me choose a home workout"))
    }

    @MainActor func testGreetingOnlyReplyGetsOneRepairWithTheOriginalQuestion() async {
        let responder = CoachResponderStub(); responder.replies = ["Hello!", "Try goblet squats, rows and presses for 2 sets of 8 reps. Rest 90 seconds between sets."]
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        store.draft = "Plan a dumbbell workout"; store.send(context: CoachContext(profile: ProfileData()))
        await store.waitForResponse()
        XCTAssertEqual(responder.questions, ["Plan a dumbbell workout", "Plan a dumbbell workout"])
        XCTAssertEqual(responder.contexts.map(\.repair), [false, true])
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages.last?.state, .complete)
        XCTAssertTrue(store.messages.last?.text.contains("goblet") == true)
    }

    @MainActor func testRepeatedGreetingFailsHonestlyAndDoesNotLoopOrKeepTheGreeting() async {
        let responder = CoachResponderStub(); responder.replies = ["Hi", "Hello"]
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        store.draft = "How do I squat?"; store.send(context: CoachContext(profile: ProfileData()))
        await store.waitForResponse()
        XCTAssertEqual(responder.questions.count, 2)
        XCTAssertEqual(store.messages.last?.state, .failed)
        XCTAssertTrue(store.messages.last?.text.isEmpty == true)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.canRetry)
    }

    func testContextScopesDefaultOffAndNeverIncludePrivateNamesOrNotes() {
        var profile = ProfileData(); profile.name = "PRIVATE NAME"; profile.currentWeightKG = 78.123; profile.primaryGoal = .strength
        var routine = Routine(name: "Training", isActive: true)
        routine.days[0].notes = "PRIVATE NOTE"
        let empty = CoachContextBuilder.build(profile: profile, permissions: CoachPermissions(), routine: routine)
        XCTAssertTrue(empty.facts.isEmpty)
        XCTAssertFalse(empty.instructions.contains("78.123"))
        let shared = CoachContextBuilder.build(profile: profile, permissions: CoachPermissions(scopes: [.profile, .training]), routine: routine)
        let prompt = shared.prompt(for: "Summarize my week", history: [])
        XCTAssertFalse(prompt.contains("PRIVATE NAME"))
        XCTAssertFalse(prompt.contains("PRIVATE NOTE"))
        XCTAssertTrue(shared.facts.contains { $0.scope == .profile })
        XCTAssertFalse(shared.facts.contains { $0.scope == .nutrition || $0.scope == .health })
    }

    private var localCalendar: Calendar {
        var value = Calendar(identifier: .iso8601); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private func day(_ day: Int, hour: Int = 12) -> Date {
        localCalendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testTrainingContextUsesRealCompletedWeightedDataAndRetainsUnknownPlanState() {
        var done = WorkoutSession(title: "Strength", startedAt: day(22), endedAt: day(22).addingTimeInterval(600), status: .completed)
        done.entries = [WorkoutEntry(exercise: ExerciseCatalogue.all[0], sets: [WorkoutSet(reps: 10, loadKG: 40, completedAt: day(22)), WorkoutSet(type: .warmup, reps: 10, loadKG: 100, completedAt: day(22))])]
        var skipped = done; skipped.id = UUID(); skipped.status = .skipped
        var future = done; future.id = UUID(); future.endedAt = day(24)
        let context = CoachContextBuilder.build(profile: ProfileData(), permissions: CoachPermissions(scopes: [.training]), sessions: [done, skipped, future], now: day(23), calendar: localCalendar)
        let week = context.facts.first { $0.id == "week" }!
        XCTAssertTrue(week.detail.contains("1 completed workouts"))
        XCTAssertTrue(week.detail.contains("400 kg·reps"))
        XCTAssertTrue(week.detail.contains("10 active minutes"))
        XCTAssertTrue(context.facts.first { $0.id == "today" }!.detail.contains("No active routine"))
        XCTAssertEqual(context.facts.filter { $0.scope != .training }.count, 0)
    }

    func testNutritionContextLabelsMissingPartialAndEstimatedValuesWithoutInventingAnAverage() {
        let food = NutritionFood(name: "Partial food", values: NutritionValues(calories: 200), estimated: true)
        let entry = FoodLogEntry(date: day(23), meal: .lunch, portion: FoodPortion(food: food))
        let context = CoachContextBuilder.build(profile: ProfileData(), permissions: CoachPermissions(scopes: [.nutrition]), foodEntries: [entry], now: day(23, hour: 18), calendar: localCalendar)
        let detail = context.facts.first { $0.id == "food" }!.detail
        XCTAssertTrue(detail.contains("200 kcal"))
        XCTAssertTrue(detail.contains("Protein: unknown"))
        XCTAssertTrue(detail.contains("1 entries use estimated"))
        XCTAssertTrue(context.facts.first { $0.id == "foodWeek" }!.detail.contains("Not enough complete"))
        XCTAssertTrue(context.facts.first { $0.id == "targets" }!.detail.contains("No shared targets"))
        XCTAssertTrue(context.facts.first { $0.id == "water" }!.detail.contains("unknown"))
        XCTAssertFalse(context.recordsSummary.contains("Calories: 0 kcal"))
    }

    func testNutritionWeeklyAverageRequiresThreeCompleteLoggedDaysAndExcludesFutureEntries() {
        let food = NutritionFood(name: "Food", values: NutritionValues(calories: 200, protein: 10, carbohydrates: 20, fat: 5))
        let entries = [20, 21, 22, 24].map { FoodLogEntry(date: day($0), meal: .lunch, portion: FoodPortion(food: food)) }
        let context = CoachContextBuilder.build(profile: ProfileData(), permissions: CoachPermissions(scopes: [.nutrition]), foodEntries: entries, now: day(23), calendar: localCalendar)
        let detail = context.facts.first { $0.id == "foodWeek" }!.detail
        XCTAssertTrue(detail.contains("3 days"))
        XCTAssertTrue(detail.contains("200 kcal"))
        XCTAssertTrue(context.facts.first { $0.id == "food" }!.detail.contains("unknown, not zero"))
    }

    func testHealthContextRejectsStaleFutureAndErrorReadingsButPreservesMeasuredZero() {
        let health = HealthOverview(waterMilliliters: .empty, steps: .init(total: 0, buckets: []), activeCalories: .init(total: 99, buckets: [], errorMessage: "Unavailable"), sleepHours: .empty)
        for timestamp in [day(22), day(24)] {
            let context = CoachContextBuilder.build(profile: ProfileData(), permissions: CoachPermissions(scopes: [.health]), health: health, healthMeasuredAt: timestamp, now: day(23), calendar: localCalendar)
            XCTAssertTrue(context.facts[0].detail.contains("No current shared readings"))
        }
        let context = CoachContextBuilder.build(profile: ProfileData(), permissions: CoachPermissions(scopes: [.health]), health: health, healthMeasuredAt: day(23), now: day(23), calendar: localCalendar)
        XCTAssertTrue(context.facts[0].detail.contains("Steps: 0 steps"))
        XCTAssertFalse(context.facts[0].detail.contains("99"))
        XCTAssertTrue(context.facts[0].detail.contains("no accessible reading"))
    }

    func testPromptSelectsRelevantFactsAndBoundsLargeRecordsWithoutTreatingLabelsAsInstructions() {
        let facts = CoachScope.allCases.map { CoachFact(id: $0.rawValue, scope: $0, title: $0.title, detail: $0.rawValue + " PRIVATE" + String(repeating: "x", count: 10_000)) }
        let context = CoachContext(profile: ProfileData(), permissions: CoachPermissions(scopes: Set(CoachScope.allCases)), facts: facts, now: day(23))
        let prompt = context.prompt(for: "Plan a workout", history: [])
        XCTAssertTrue(prompt.contains("training PRIVATE"))
        XCTAssertFalse(prompt.contains("nutrition PRIVATE"))
        XCTAssertFalse(prompt.contains("health PRIVATE"))
        XCTAssertLessThan(prompt.count, 3_000)
        XCTAssertTrue(context.instructions.contains("untrusted data"))
        XCTAssertEqual(CoachTopic.resolve("How many calories did I burn?"), .health)
    }

    func testTechniqueQuestionsRetrieveSpecificBundledReferencesWithoutNeedingPersonalSharing() {
        let references = CoachExerciseReference.matches("How do I do a front squat?")
        XCTAssertEqual(references.first?.name, "Front squat")
        XCTAssertEqual(references.count, 1)
        XCTAssertFalse(references[0].technique.isEmpty)
        let context = CoachContext(profile: ProfileData())
        let prompt = context.prompt(for: "How do I bench press?", history: [])
        XCTAssertTrue(prompt.contains("Bench press"))
        XCTAssertTrue(prompt.contains("spotter"))
        XCTAssertTrue(context.permissions.scopes.isEmpty)
        XCTAssertTrue(CoachExerciseReference.matches("Hello").isEmpty)
    }

    func testArchiveRejectsUnknownVersionAndInvalidPrivacyBoundary() {
        var archive = CoachArchive(); archive.version = 2
        XCTAssertThrowsError(try archive.validate())
        let chat = CoachChat(id: UUID(), title: "Chat", updatedAt: .now, messages: [], contextStartIndex: 10)
        XCTAssertThrowsError(try CoachArchive(chats: [chat]).validate())
    }

    @MainActor func testRefreshingFactsDoesNotLoseFollowUpButChangingPermissionsDoes() async {
        let responder = CoachResponderStub()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        let permissions = CoachPermissions(scopes: [.training])
        let first = CoachContext(profile: ProfileData(), permissions: permissions, facts: [.init(id: "count", scope: .training, title: "Workouts", detail: "1 workout")])
        store.draft = "Review my training"; store.send(context: first); await store.waitForResponse()
        var updated = first; updated.facts = [.init(id: "count", scope: .training, title: "Workouts", detail: "2 workouts")]
        store.draft = "What should I improve?"; store.send(context: updated); await store.waitForResponse()
        XCTAssertEqual(responder.histories[1].count, 2)
        store.draft = "What about technique?"; store.send(context: CoachContext(profile: ProfileData())); await store.waitForResponse()
        XCTAssertTrue(responder.histories[2].isEmpty)
    }

    @MainActor func testRecordsSummaryWorksWithoutModelAndIsClearlyMarked() {
        let responder = CoachResponderStub()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .unavailable(.deviceNotEligible)), responder: responder)
        let context = CoachContextBuilder.build(profile: ProfileData(), permissions: CoachPermissions(scopes: [.training]), now: day(23), calendar: localCalendar)
        store.showRecords(context: context)
        XCTAssertEqual(responder.questions.count, 0)
        XCTAssertEqual(store.messages.last?.source, .records)
        XCTAssertTrue(store.messages.last?.text.contains("Calculated from shared records") == true)
        XCTAssertFalse(store.canSend)
    }

    @MainActor func testFileArchiveRelaunchNewSelectDeleteAndRevocationKeepPrivacyBoundary() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CoachTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = FileCoachPersistence(url: folder.appendingPathComponent("chats.json"))
        let capability = CoachCapabilityStub(status: .available), responder = CoachResponderStub()
        let store = CoachStore(capabilities: capability, responder: responder, persistence: file)
        store.setPermission(.training, enabled: true)
        let shared = CoachContext(profile: ProfileData(), permissions: store.permissions)
        store.draft = "Review private training data"; store.send(context: shared); await store.waitForResponse()
        let firstID = try XCTUnwrap(store.selectedID)
        store.newChat()
        store.draft = "Explain a squat"; store.send(context: shared); await store.waitForResponse()
        let secondID = try XCTUnwrap(store.selectedID)
        XCTAssertNotEqual(firstID, secondID); XCTAssertEqual(store.chats.count, 2)
        store.setPermission(.training, enabled: false)
        let reopened = CoachStore(capabilities: capability, responder: responder, persistence: file)
        XCTAssertEqual(reopened.messages.first?.text, "Explain a squat")
        XCTAssertFalse(reopened.permissions.includes(.training))
        reopened.selectChat(firstID)
        reopened.draft = "What next?"; reopened.send(context: CoachContext(profile: ProfileData())); await reopened.waitForResponse()
        XCTAssertTrue(responder.histories.last!.isEmpty)
        reopened.deleteChat(firstID)
        XCTAssertTrue(reopened.messages.isEmpty)
        XCTAssertEqual(try file.load().chats.map(\.id), [secondID])
        reopened.clear()
        XCTAssertTrue(try file.load().chats.isEmpty)
        XCTAssertTrue(reopened.permissions.scopes.isEmpty)
    }

    @MainActor func testInterruptedReplyRestoresStoppedAndCanRetry() throws {
        let storage = MemoryCoachPersistence()
        let user = CoachMessage(role: .user, text: "How should I warm up?")
        let reply = CoachMessage(role: .assistant, text: "Start with", state: .responding)
        let chat = CoachChat(id: UUID(), title: user.text, updatedAt: .now, messages: [user, reply])
        storage.archive = CoachArchive(chats: [chat], selectedID: chat.id)
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), persistence: storage)
        XCTAssertEqual(store.messages.last?.state, .stopped)
        XCTAssertTrue(store.canRetry)
        XCTAssertFalse(store.isResponding)
    }

    @MainActor func testCorruptArchiveCannotBeOverwrittenUntilExplicitDeletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CoachCorrupt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("chats.json"), original = Data("preserve me".utf8)
        try original.write(to: url)
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), persistence: FileCoachPersistence(url: url))
        XCTAssertFalse(store.archiveLoaded)
        XCTAssertNotNil(store.storageError)
        store.draft = "Help"; store.send(context: CoachContext(profile: ProfileData()))
        store.newChat(); store.retryStorage()
        XCTAssertEqual(try Data(contentsOf: url), original)
        store.clear()
        XCTAssertTrue(store.archiveLoaded)
        XCTAssertTrue(try FileCoachPersistence(url: url).load().chats.isEmpty)
    }

    @MainActor func testWriteFailureIsVisibleAndRetrySavesWithoutLosingMessages() async {
        let storage = CoachFailingPersistence()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: CoachResponderStub(), persistence: storage)
        store.draft = "How do I row?"; store.send(context: CoachContext(profile: ProfileData())); await store.waitForResponse()
        XCTAssertNotNil(store.storageError)
        XCTAssertEqual(store.messages.count, 2)
        storage.failWrites = false; store.retryStorage()
        XCTAssertNil(store.storageError)
        XCTAssertEqual(storage.archive.chats.first?.messages.count, 2)
    }

    @MainActor func testStoppingInFlightOrDeletingAllRejectsLateUncooperativeReply() async {
        let responder = CoachSuspendingResponder()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder)
        store.draft = "How do I squat?"; store.send(context: CoachContext(profile: ProfileData()))
        for _ in 0..<20 where !responder.started { await Task.yield() }
        XCTAssertTrue(responder.started)
        store.clear()
        responder.finish()
        await Task.yield()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.isResponding)
    }

    @MainActor func testTimeoutRetainsQuestionAndExposesRetry() async {
        let responder = CoachSuspendingResponder()
        let store = CoachStore(capabilities: CoachCapabilityStub(status: .available), responder: responder, timeout: .milliseconds(10))
        store.draft = "How do I squat?"; store.send(context: CoachContext(profile: ProfileData()))
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(store.isResponding)
        XCTAssertEqual(store.messages.last?.state, .failed)
        XCTAssertTrue(store.errorMessage?.contains("too long") == true)
        XCTAssertTrue(store.canRetry)
        responder.finish()
        await Task.yield()
        XCTAssertEqual(store.messages.last?.state, .failed)
    }
}

@MainActor private final class CoachCapabilityStub: RuntimeCapabilityProviding {
    var status: CapabilityStatus
    init(status: CapabilityStatus) { self.status = status }
    func currentCapabilities() -> CapabilitySnapshot {
        .init(healthKit: .unavailable(.systemUnavailable), foundationModels: status,
              imagePlayground: .unavailable(.systemUnavailable))
    }
}

@MainActor private final class CoachResponderStub: CoachResponding {
    var questions: [String] = []
    var histories: [[CoachMessage]] = []
    var shouldFail = false
    var replies: [String] = []
    var contexts: [CoachContext] = []
    func reply(to question: String, history: [CoachMessage], context: CoachContext,
               onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        questions.append(question)
        histories.append(history)
        contexts.append(context)
        onUpdate("A focused")
        if shouldFail { throw CoachFailure.emptyResponse }
        return replies.isEmpty ? "A focused fitness reply." : replies.removeFirst()
    }
}

@MainActor private final class CoachFailingPersistence: CoachPersisting {
    var archive = CoachArchive()
    var failWrites = true
    func load() throws -> CoachArchive { archive }
    func save(_ archive: CoachArchive) throws { if failWrites { throw CocoaError(.fileWriteOutOfSpace) }; self.archive = archive }
    func delete() throws { archive = CoachArchive() }
}

@MainActor private final class CoachSuspendingResponder: CoachResponding {
    var started = false
    private var continuation: CheckedContinuation<String, Never>?
    private var update: ((String) -> Void)?
    func reply(to question: String, history: [CoachMessage], context: CoachContext,
               onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        started = true; update = onUpdate
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { update?("Late reply"); continuation?.resume(returning: "Keep your heels down and use a controlled range of motion."); continuation = nil }
}

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
    func reply(to question: String, history: [CoachMessage], context: CoachContext,
               onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        questions.append(question)
        histories.append(history)
        onUpdate("A focused")
        if shouldFail { throw CoachFailure.emptyResponse }
        return "A focused fitness reply."
    }
}

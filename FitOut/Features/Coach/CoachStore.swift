import Foundation
import Observation

struct CoachMessage: Identifiable, Equatable, Codable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    enum State: String, Codable, Sendable { case complete, responding, stopped, failed }
    enum Source: String, Codable, Sendable { case model, records }
    let id: UUID
    let role: Role
    var text: String
    var state: State = .complete
    var date: Date
    var source: Source
    var sharedScopes: [CoachScope]

    init(id: UUID = UUID(), role: Role, text: String, state: State = .complete,
         date: Date = .now, source: Source = .model, sharedScopes: [CoachScope] = []) {
        self.id = id; self.role = role; self.text = text; self.state = state
        self.date = date; self.source = source; self.sharedScopes = sharedScopes
    }
}

enum CoachConversation {
    static let maximumMessageLength = 1_200
    static func history(from messages: [CoachMessage]) -> [CoachMessage] {
        var pairs: [[CoachMessage]] = [], user: CoachMessage?
        for message in messages {
            if message.role == .user { user = message }
            else if let question = user {
                if message.state == .complete && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    pairs.append([question, message])
                }
                user = nil
            }
        }
        var selected: [[CoachMessage]] = [], characters = 0
        for pair in pairs.suffix(3).reversed() {
            let length = pair.reduce(0) { $0 + $1.text.count }
            guard characters + length <= 3_000 else { break }
            selected.insert(pair, at: 0); characters += length
        }
        return selected.flatMap { $0 }
    }
}

enum CoachReplyQuality {
    static func accepts(_ text: String, question: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 6_000 else { return false }
        let normalized = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        let greetings = ["hi", "hello", "hey", "hi there", "hello there", "how can i help", "how can i help you", "how can i help you today", "what can i help you with", "i am your fitness coach", "i m your fitness coach"]
        var remainder = normalized
        for phrase in greetings.sorted(by: { $0.count > $1.count }) { remainder = remainder.replacingOccurrences(of: phrase, with: " ") }
        let greetingOnly = remainder.trimmingCharacters(in: .whitespaces).isEmpty
        // A simple greeting may receive a short reply. A real question must not.
        let questionWords = question.lowercased().split { !$0.isLetter }.map(String.init)
        let isGreeting = !questionWords.isEmpty && questionWords.allSatisfy { ["hi", "hello", "hey", "there", "coach"].contains($0) }
        if greetingOnly && !isGreeting { return false }
        let isIntroduction = ["hi ", "hello ", "hey ", "i am fitout", "i m fitout"].contains { normalized.hasPrefix($0) }
        let justOffersHelp = ["how can i", "how may i", "here to help", "what would you like", "let me know", "can assist"].contains(where: normalized.contains)
        if !isGreeting && isIntroduction && justOffersHelp && normalized.split(separator: " ").count <= 35 { return false }
        let falseWrites = ["i saved your", "i ve saved your", "i updated your", "i logged your", "i scheduled your", "i changed your", "i deleted your"]
        return !falseWrites.contains(where: normalized.contains)
    }
}

enum CoachFailure: Error {
    case unavailable, emptyResponse, contextTooLong, unsupportedLanguage, declined, unhelpfulResponse, timedOut
    var message: String {
        switch self {
        case .unavailable: "On-device AI is unavailable. You can still view your calculated record summary."
        case .emptyResponse, .unhelpfulResponse: "The coach didn't produce a useful answer. Retry, or ask a more specific exercise, workout or food question. Your records summary remains available."
        case .contextTooLong: "This question exceeds the model's context budget. Shorten it or start a new chat."
        case .unsupportedLanguage: "The on-device model doesn't support this language or region. Try a supported language."
        case .declined: "The coach couldn't answer that request. Try a general training or nutrition question."
        case .timedOut: "The on-device reply took too long. Your question is saved; retry when the model is ready."
        }
    }
}

@MainActor protocol CoachResponding {
    func reply(to question: String, history: [CoachMessage], context: CoachContext,
               onUpdate: @escaping @MainActor (String) -> Void) async throws -> String
}

@MainActor @Observable final class CoachStore {
    private(set) var messages: [CoachMessage] = []
    private(set) var chats: [CoachChat] = []
    private(set) var selectedID: UUID?
    private(set) var permissions = CoachPermissions()
    private(set) var availability: CapabilityStatus
    private(set) var isResponding = false
    private(set) var errorMessage: String?
    private(set) var storageError: String?
    private(set) var archiveLoaded = false
    var draft = ""
    var onFeedback: ((FitHapticEvent) -> Void)?
    var usesProfileGoal: Bool {
        get { permissions.includes(.profile) }
        set { setPermission(.profile, enabled: newValue) }
    }
    @ObservationIgnored private let capabilities: any RuntimeCapabilityProviding
    @ObservationIgnored private let responder: any CoachResponding
    @ObservationIgnored private let persistence: any CoachPersisting
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private var retryMessageID: UUID?
    @ObservationIgnored private var lastPrivacySignature: String?
    @ObservationIgnored private var contextStartIndex = 0

    init(capabilities: any RuntimeCapabilityProviding, responder: any CoachResponding = OnDeviceCoachResponder(),
         persistence: (any CoachPersisting)? = nil, timeout: Duration = .seconds(60)) {
        self.capabilities = capabilities; self.responder = responder
        self.persistence = persistence ?? MemoryCoachPersistence(); self.timeout = timeout
        availability = capabilities.currentCapabilities().foundationModels
        load()
    }
    var canSend: Bool {
        archiveLoaded && availability.isAvailable && !isResponding &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.count <= CoachConversation.maximumMessageLength
    }
    var canRetry: Bool { archiveLoaded && retryMessageID != nil && availability.isAvailable && !isResponding }
    var orderedChats: [CoachChat] { chats.sorted { $0.updatedAt > $1.updatedAt } }

    func refreshAvailability() {
        availability = capabilities.currentCapabilities().foundationModels
        if !availability.isAvailable { stop() }
    }
    func setPermission(_ scope: CoachScope, enabled: Bool) {
        guard archiveLoaded, permissions.includes(scope) != enabled else { return }
        stop()
        if enabled { permissions.scopes.insert(scope) } else { permissions.scopes.remove(scope) }
        // This boundary is saved with the conversation, not just kept in memory.
        contextStartIndex = messages.count; lastPrivacySignature = nil
        persist()
    }
    func send(context: CoachContext) {
        refreshAvailability()
        guard canSend else { return }
        let user = CoachMessage(role: .user, text: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        draft = ""; messages.append(user)
        onFeedback?(.selection)
        beginReply(to: user, context: context)
    }
    func retry(context: CoachContext) {
        refreshAvailability()
        guard canRetry, let retryMessageID, let user = messages.first(where: { $0.id == retryMessageID }),
              let index = messages.firstIndex(where: { $0.id == user.id }) else { return }
        messages = Array(messages.prefix(index + 1))
        contextStartIndex = min(contextStartIndex, messages.count - 1)
        beginReply(to: user, context: context)
    }
    func showRecords(context: CoachContext) {
        guard archiveLoaded, !isResponding else { return }
        alignPrivacy(context)
        messages.append(CoachMessage(role: .user, text: "Show my shared records"))
        messages.append(CoachMessage(role: .assistant, text: context.recordsSummary, source: .records,
                                     sharedScopes: context.permissions.scopes.sorted { $0.rawValue < $1.rawValue }))
        retryMessageID = nil; errorMessage = nil; persist()
        onFeedback?(.selection)
    }
    func stop() {
        guard isResponding else { return }
        cancelTasks()
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.state == .responding }) { messages[index].state = .stopped }
        retryMessageID = messages.last(where: { $0.role == .user })?.id
        persist()
    }
    func newChat() {
        stop(); persist()
        selectedID = nil; messages = []; draft = ""; retryMessageID = nil
        lastPrivacySignature = nil; contextStartIndex = 0; errorMessage = nil
        persist()
    }
    func selectChat(_ id: UUID) {
        guard archiveLoaded, selectedID != id else { return }
        stop(); persist()
        guard let chat = chats.first(where: { $0.id == id }) else { return }
        restore(chat); draft = ""; errorMessage = nil; persist()
    }
    func deleteChat(_ id: UUID) {
        guard archiveLoaded else { return }
        if selectedID == id {
            stop(); selectedID = nil; messages = []; draft = ""
            retryMessageID = nil; contextStartIndex = 0; lastPrivacySignature = nil; errorMessage = nil
        }
        chats.removeAll { $0.id == id }; persist()
    }
    /// Explicit delete-all also recovers an unreadable archive, only after UI confirmation.
    func clear() {
        stop()
        do {
            try persistence.delete()
            messages = []; chats = []; selectedID = nil; draft = ""
            retryMessageID = nil; lastPrivacySignature = nil; contextStartIndex = 0
            permissions = CoachPermissions(); errorMessage = nil; storageError = nil; archiveLoaded = true
            persist()
        } catch { storageError = "Couldn't delete saved chats. Try again. Your saved file is preserved." }
    }
    func retryStorage() { if archiveLoaded { persist() } else { load() } }
    func waitForResponse() async { let task = responseTask; await task?.value }

    private func alignPrivacy(_ context: CoachContext) {
        if lastPrivacySignature != context.privacySignature {
            contextStartIndex = max(contextStartIndex, max(0, messages.count - 1))
            lastPrivacySignature = context.privacySignature
        }
    }
    private func beginReply(to user: CoachMessage, context: CoachContext) {
        alignPrivacy(context)
        let history = CoachConversation.history(from: Array(messages.dropFirst(contextStartIndex).dropLast()))
        let scopes = context.relevantFacts(for: user.text).map(\.scope)
        let assistant = CoachMessage(role: .assistant, text: "", state: .responding,
                                     sharedScopes: Array(Set(scopes)).sorted { $0.rawValue < $1.rawValue })
        messages.append(assistant)
        let id = UUID(); requestID = id; retryMessageID = nil; errorMessage = nil; isResponding = true
        persist() // Save the question and interrupted-reply marker before generation.
        responseTask = Task { [weak self] in
            guard let self, self.requestID == id, !Task.isCancelled else { return }
            do {
                var accepted: String?
                for attempt in 0..<2 {
                    try Task.checkCancellation()
                    var requestContext = context; requestContext.repair = attempt > 0
                    let text = try await responder.reply(to: user.text, history: history, context: requestContext) { [weak self] text in
                        guard let self, self.requestID == id,
                              let index = self.messages.firstIndex(where: { $0.id == assistant.id }) else { return }
                        self.messages[index].text = String(text.prefix(6_000))
                    }
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    if CoachReplyQuality.accepts(text, question: user.text) { accepted = text; break }
                    if let index = messages.firstIndex(where: { $0.id == assistant.id }) { messages[index].text = "" }
                }
                guard let accepted else { throw CoachFailure.unhelpfulResponse }
                guard requestID == id, let index = messages.firstIndex(where: { $0.id == assistant.id }) else { return }
                messages[index].text = accepted; messages[index].state = .complete
                onFeedback?(.coachReply)
                cancelTasks(); persist()
            } catch {
                guard requestID == id else { return }
                fail((error as? CoachFailure) ?? .emptyResponse)
            }
        }
        timeoutTask = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.requestID == id else { return }
            self.fail(.timedOut)
        }
    }
    private func fail(_ failure: CoachFailure) {
        cancelTasks()
        availability = capabilities.currentCapabilities().foundationModels
        if let index = messages.lastIndex(where: { $0.role == .assistant && $0.state == .responding }) { messages[index].state = .failed }
        errorMessage = failure.message; retryMessageID = messages.last(where: { $0.role == .user })?.id
        persist()
    }
    private func cancelTasks() {
        requestID = nil; responseTask?.cancel(); responseTask = nil
        timeoutTask?.cancel(); timeoutTask = nil; isResponding = false
    }
    private func load() {
        do {
            let archive = try persistence.load(); try archive.validate()
            chats = archive.chats; permissions = archive.permissions; selectedID = archive.selectedID
            archiveLoaded = true; storageError = nil
            if let chat = chats.first(where: { $0.id == selectedID }) { restore(chat) }
        } catch {
            archiveLoaded = false; storageError = "Saved chats could not be opened. The original file is preserved. Retry or delete all chats to start again."
        }
    }
    private func restore(_ chat: CoachChat) {
        selectedID = chat.id; messages = chat.messages.map { message in
            var value = message; if value.state == .responding { value.state = .stopped }; return value
        }
        contextStartIndex = chat.contextStartIndex; lastPrivacySignature = chat.privacySignature
        retryMessageID = messages.last?.state == .stopped || messages.last?.state == .failed ? messages.last(where: { $0.role == .user })?.id : nil
    }
    private func persist() {
        guard archiveLoaded else { return } // Never overwrite an unreadable archive.
        if !messages.isEmpty {
            let id = selectedID ?? UUID(); selectedID = id
            let chat = CoachChat(id: id, title: String((messages.first(where: { $0.role == .user })?.text ?? "Conversation").prefix(70)),
                                 updatedAt: .now, messages: messages, contextStartIndex: contextStartIndex, privacySignature: lastPrivacySignature)
            if let index = chats.firstIndex(where: { $0.id == id }) { chats[index] = chat } else { chats.append(chat) }
        }
        do {
            try persistence.save(CoachArchive(permissions: permissions, chats: chats, selectedID: selectedID))
            storageError = nil
        } catch { storageError = "Your latest chat changes could not be saved. Keep FitOut open and retry saving." }
    }
}

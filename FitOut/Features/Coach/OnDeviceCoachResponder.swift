import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct CoachGeneratedReply {
    @Guide(description: "Answer the actual fitness or nutrition question directly. Include concrete steps or an example; do not merely greet or offer help.")
    var answer: String
    @Guide(description: "One practical next step justified by the answer or shared facts. Empty string when not useful. Never claim that app data was changed.")
    var nextStep: String
    @Guide(description: "At most one important clarifying question. Empty string when the answer needs no question.")
    var question: String
}
#endif

@MainActor struct OnDeviceCoachResponder: CoachResponding {
    func reply(to question: String, history: [CoachMessage], context: CoachContext,
               onUpdate: @escaping @MainActor (String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            // The repair starts fresh to avoid reinforcing a greeting-only exchange.
            var boundedHistory = context.repair ? [] : history
            var prompt = context.prompt(for: question, history: history)
            var entries = transcript(instructions: context.instructions, history: boundedHistory)
            if #available(iOS 26.4, *) {
                let model = SystemLanguageModel.default
                let schemaTokens = try await model.tokenCount(for: CoachGeneratedReply.generationSchema)
                while true {
                    let used = try await model.tokenCount(for: entries) + model.tokenCount(for: prompt)
                    if used + schemaTokens + 900 <= model.contextSize { break }
                    guard !boundedHistory.isEmpty else { throw CoachFailure.contextTooLong }
                    boundedHistory.removeFirst(min(2, boundedHistory.count))
                    entries = transcript(instructions: context.instructions, history: boundedHistory)
                }
            }
            var retriedContext = false
            while true {
                let session = LanguageModelSession(transcript: Transcript(entries: entries))
                var text = ""
                do {
                    for try await snapshot in session.streamResponse(to: prompt, generating: CoachGeneratedReply.self,
                        options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 768)) {
                        try Task.checkCancellation()
                        text = [snapshot.content.answer, snapshot.content.nextStep, snapshot.content.question]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }.joined(separator: "\n\n")
                        onUpdate(text)
                    }
                    try Task.checkCancellation()
                    return text
                } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                    // Older OS versions have no token counter. One context-free retry
                    // still retains the latest permitted app facts and actual question.
                    guard !retriedContext, !boundedHistory.isEmpty else { throw CoachFailure.contextTooLong }
                    retriedContext = true; boundedHistory = []
                    entries = transcript(instructions: context.instructions, history: [])
                    prompt = context.prompt(for: question, history: [])
                    onUpdate("")
                } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale { throw CoachFailure.unsupportedLanguage }
                catch LanguageModelSession.GenerationError.guardrailViolation { throw CoachFailure.declined }
                catch LanguageModelSession.GenerationError.refusal { throw CoachFailure.declined }
                catch {
                    if #available(iOS 27.0, *), let failure = error as? LanguageModelError {
                        switch failure {
                        case .contextSizeExceeded: throw CoachFailure.contextTooLong
                        case .unsupportedLanguageOrLocale: throw CoachFailure.unsupportedLanguage
                        case .guardrailViolation, .refusal: throw CoachFailure.declined
                        case .timeout: throw CoachFailure.timedOut
                        default: break
                        }
                    }
                    throw error
                }
            }
        }
        #endif
        throw CoachFailure.unavailable
    }
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func transcript(instructions: String, history: [CoachMessage]) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = [.instructions(.init(segments: [.text(.init(content: instructions))], toolDefinitions: []))]
        for message in history {
            let segments: [Transcript.Segment] = [.text(.init(content: message.text))]
            if message.role == .user { entries.append(.prompt(.init(segments: segments))) }
            else { entries.append(.response(.init(assetIDs: [], segments: segments))) }
        }
        return entries
    }
    #endif
}

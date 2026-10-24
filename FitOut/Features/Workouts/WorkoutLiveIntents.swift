import Foundation
import AppIntents

struct WorkoutLiveIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control FitOut workout"
    static let description = IntentDescription("Pauses, resumes, starts a set or adjusts rest for the displayed workout.")
    static let openAppWhenRun = false
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @Parameter(title: "Workout identifier") var sessionID: String
    @Parameter(title: "Command identifier") var commandID: String
    @Parameter(title: "Action") var operation: String
    init() { sessionID = ""; commandID = ""; operation = "pause" }
    init(sessionID: UUID, commandID: UUID, operation: String) {
        self.sessionID = sessionID.uuidString; self.commandID = commandID.uuidString; self.operation = operation
    }
    func perform() async throws -> some IntentResult {
        guard let session = UUID(uuidString: sessionID), let command = UUID(uuidString: commandID),
              ["pause", "resume", "startSet", "endRest", "extendRest"].contains(operation) else { throw WorkoutLiveActionError.invalidCommand }
        try await execute(session: session, command: command)
        return .result()
    }
    private func execute(session: UUID, command: UUID) async throws {
        #if FITOUT_WIDGET_EXTENSION
        // LiveActivityIntent is run by iOS in the containing app, not in this extension.
        throw WorkoutLiveActionError.appProcessOnly
        #else
        try await WorkoutRuntime.perform(operation: operation, sessionID: session, commandID: command)
        #endif
    }
}

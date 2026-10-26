import Foundation

struct CoachChat: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var updatedAt: Date
    var messages: [CoachMessage]
    var contextStartIndex = 0
    var privacySignature: String?
}

struct CoachArchive: Codable, Equatable {
    var version = 1
    var permissions = CoachPermissions()
    var chats: [CoachChat] = []
    var selectedID: UUID?

    func validate() throws {
        guard version == 1, Set(chats.map(\.id)).count == chats.count,
              selectedID == nil || chats.contains(where: { $0.id == selectedID }),
              chats.allSatisfy({ chat in
                  Set(chat.messages.map(\.id)).count == chat.messages.count &&
                  (0...chat.messages.count).contains(chat.contextStartIndex) &&
                  chat.messages.allSatisfy { $0.text.count <= 12_000 }
              }) else { throw CoachStorageFailure.unreadable }
    }
}

enum CoachStorageFailure: LocalizedError {
    case unreadable
    var errorDescription: String? { "Saved chats could not be opened. The existing file is preserved. Retry, or explicitly delete all chats to start again." }
}

@MainActor protocol CoachPersisting {
    func load() throws -> CoachArchive
    func save(_ archive: CoachArchive) throws
    func delete() throws
}

@MainActor final class FileCoachPersistence: CoachPersisting {
    let url: URL
    init(url: URL) { self.url = url }
    func load() throws -> CoachArchive {
        guard FileManager.default.fileExists(atPath: url.path) else { return CoachArchive() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 32_000_000 else { throw CoachStorageFailure.unreadable }
        let value = try JSONDecoder().decode(CoachArchive.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
    func save(_ archive: CoachArchive) throws {
        try archive.validate()
        let data = try JSONEncoder().encode(archive)
        guard data.count <= 32_000_000 else { throw CoachStorageFailure.unreadable }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.deletingLastPathComponent().path)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

@MainActor final class MemoryCoachPersistence: CoachPersisting {
    var archive = CoachArchive()
    func load() throws -> CoachArchive { archive }
    func save(_ archive: CoachArchive) throws { self.archive = archive }
    func delete() throws { archive = CoachArchive() }
}

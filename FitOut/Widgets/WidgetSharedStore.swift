import Foundation
import Darwin

enum WidgetStoreError: LocalizedError {
    case appGroupUnavailable, unsupportedVersion, invalidAmount, invalidGoals, lockFailed, entryUnavailable
    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable: "Shared widget storage is unavailable. Enable the FitOut App Group for both app and widget targets in Signing & Capabilities."
        case .unsupportedVersion: "This widget data needs a newer version of FitOut. Open or update the app."
        case .invalidAmount: "Choose a water amount between 1 and 5,000 ml."
        case .invalidGoals: "Check the goal values, or leave them blank."
        case .lockFailed: "Widget data is temporarily busy. Try again."
        case .entryUnavailable: "This water entry was removed. Refresh the history before editing it."
        }
    }
}

/// A separate, atomic App Group cache leaves the existing SwiftData store in place.
/// All read/modify/write operations take a process-shared lock, including App Intents.
struct WidgetSharedStore: Sendable {
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    static func live() throws -> Self {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: FitOutWidgetID.appGroup) else { throw WidgetStoreError.appGroupUnavailable }
        return Self(directory: root.appendingPathComponent("Widgets", isDirectory: true))
    }
    func read() throws -> FitOutWidgetState { try locked { try load() } }
    @discardableResult func update(_ change: (inout FitOutWidgetState) throws -> Void) throws -> FitOutWidgetState {
        try locked {
            var state = try load()
            try change(&state)
            let data = try JSONEncoder().encode(state)
            try data.write(to: directory.appendingPathComponent("state.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return state
        }
    }
    @discardableResult func logWater(_ milliliters: Int, at date: Date = .now) throws -> FitOutWidgetState {
        guard (1...5_000).contains(milliliters) else { throw WidgetStoreError.invalidAmount }
        return try update { $0.water.append(WidgetWaterLog(date: date, milliliters: milliliters)) }
    }
    @discardableResult func removeWater(id: UUID) throws -> FitOutWidgetState {
        // Remove the exact displayed entry. A stale undo must never remove a newer log.
        try update { $0.water.removeAll { $0.id == id } }
    }
    @discardableResult func editWater(id: UUID, milliliters: Int, date: Date) throws -> FitOutWidgetState {
        guard (1...5_000).contains(milliliters), date <= Date().addingTimeInterval(60) else { throw WidgetStoreError.invalidAmount }
        return try update { state in
            guard let index = state.water.firstIndex(where: { $0.id == id }) else { throw WidgetStoreError.entryUnavailable }
            state.water[index] = WidgetWaterLog(id: id, date: date, milliliters: milliliters)
        }
    }
    @discardableResult func saveGoals(_ goals: WidgetGoals) throws -> FitOutWidgetState {
        guard goals.isValid else { throw WidgetStoreError.invalidGoals }
        return try update { $0.goals = goals }
    }
    private func load() throws -> FitOutWidgetState {
        let file = directory.appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return FitOutWidgetState() }
        let value = try JSONDecoder().decode(FitOutWidgetState.self, from: Data(contentsOf: file))
        guard value.version == 1 else { throw WidgetStoreError.unsupportedVersion }
        return value
    }
    private func locked<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let descriptor = directory.appendingPathComponent("state.lock").path.withCString { Darwin.open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR) }
        guard descriptor >= 0 else { throw WidgetStoreError.lockFailed }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw WidgetStoreError.lockFailed }
        defer { flock(descriptor, LOCK_UN) }
        return try work()
    }
}

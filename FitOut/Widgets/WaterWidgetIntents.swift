import Foundation
import AppIntents
import WidgetKit

struct LogWidgetWater: AppIntent {
    static let title: LocalizedStringResource = "Log water in FitOut"
    static let description = IntentDescription("Records water in FitOut without opening the app.")
    static let openAppWhenRun = false
    static let isDiscoverable = false
    @Parameter(title: "Milliliters") var milliliters: Int
    init() { milliliters = 150 }
    init(milliliters: Int) { self.milliliters = milliliters }
    func perform() async throws -> some IntentResult {
        guard [150, 250, 500, 750].contains(milliliters) else { throw WidgetStoreError.invalidAmount }
        let store = try WidgetSharedStore.live()
        guard try store.read().snapshot.onboarded else { throw WidgetActionError.finishSetup }
        try store.logWater(milliliters)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
struct UndoWidgetWater: AppIntent {
    static let title: LocalizedStringResource = "Undo water log in FitOut"
    static let openAppWhenRun = false
    static let isDiscoverable = false
    @Parameter(title: "Log identifier") var logID: String
    init() { logID = "" }
    init(logID: UUID) { self.logID = logID.uuidString }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: logID) else { throw WidgetStoreError.invalidAmount }
        try WidgetSharedStore.live().removeWater(id: id)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
enum WidgetActionError: LocalizedError {
    case finishSetup
    var errorDescription: String? { "Open FitOut and finish onboarding before logging water." }
}

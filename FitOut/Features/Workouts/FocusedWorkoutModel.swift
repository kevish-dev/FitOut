import Foundation
import Observation

extension WorkoutStore {
    @discardableResult func prepareFocusedSession(_ id: UUID, now: Date = .now) -> Bool {
        guard var session = sessions.first(where: { $0.id == id }) else { return false }
        let before = session
        WorkoutExecutionEngine.prepare(&session, at: now)
        return session == before || save(session, before: before, at: now)
    }
    @discardableResult func performFocused(_ command: WorkoutCommand, sessionID: UUID, expectedSet: UUID? = nil,
        now: Date = .now, origin: WorkoutEventOrigin = .app, receipt: String? = nil) -> Bool {
        guard var session = sessions.first(where: { $0.id == sessionID }) else { error = "This workout is no longer available."; return false }
        if let receipt, session.telemetry?.actionReceipts.contains(receipt) == true { return true }
        if command == .undo, let other = active, other.id != sessionID {
            error = "End the current workout before restoring this session."; return false
        }
        let before = session
        do {
            _ = try WorkoutExecutionEngine.apply(command, to: &session, expectedSet: expectedSet, at: now)
            if let receipt { session.telemetry?.actionReceipts.append(receipt) }
            guard session != before else { error = nil; return true }
            return save(session, before: before, at: now, origin: origin)
        } catch { self.error = error.localizedDescription; return false }
    }
}

/// A monotonic foreground anchor avoids tick-count drift. Relaunch/foreground
/// recovery deliberately reanchors to saved wall timestamps.
struct WorkoutClockAnchor {
    private let wall: Date
    private let instant: ContinuousClock.Instant
    init(wall: Date = .now) { self.wall = wall; instant = .now }
    var now: Date {
        let elapsed = instant.duration(to: .now).components
        return wall.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
}

@MainActor @Observable final class FocusedWorkoutModel {
    let store: WorkoutStore
    let sessionID: UUID?
    let defaultUnit: WeightUnit
    private(set) var inputErrors: [WorkoutInputField: String] = [:]
    var editingInputs: Set<WorkoutInputField> = []
    var inputError: String? { inputErrors.values.sorted().first }
    @ObservationIgnored private var anchor = WorkoutClockAnchor()
    @ObservationIgnored private var restTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledDeadline: Date?
    @ObservationIgnored private var visible = false
    @ObservationIgnored private var inputSetID: UUID?
    init(store: WorkoutStore, unit: WeightUnit) { self.store = store; sessionID = store.active?.id; defaultUnit = unit }
    var session: WorkoutSession? { store.sessions.first { $0.id == sessionID } }
    var phase: WorkoutPhase { session?.execution?.phase ?? .ready }
    var current: (entry: WorkoutEntry, set: WorkoutSet)? { session?.executingWork }
    var unit: WeightUnit { store.displayWeightUnit ?? defaultUnit }
    var now: Date { anchor.now }
    var next: WorkoutEntry? {
        guard let session else { return nil }
        let next = session.pendingWork.first { $0.setID != session.execution?.setID }
        return session.entries.first { $0.id == next?.entryID }
    }
    func activate() { visible = true; anchor = WorkoutClockAnchor(); refresh() }
    func deactivate() { visible = false; restTask?.cancel(); restTask = nil; scheduledDeadline = nil }
    func refresh() {
        if let sessionID { _ = store.prepareFocusedSession(sessionID, now: now) }
        if inputSetID != current?.set.id { inputSetID = current?.set.id; inputErrors = [:]; editingInputs = [] }
        scheduleRest()
    }
    func editDisplayedLoad(_ number: Double, unit inputUnit: WeightUnit, setID: UUID) {
        guard inputUnit == unit, var value = current?.set, value.id == setID else { return }
        value.loadKG = inputUnit.kilograms(number)
        editSet(value, field: .load)
    }
    func perform(_ command: WorkoutCommand, expectedSet: UUID? = nil) {
        guard let sessionID else { return }
        if command == .completeSet {
            guard editingInputs.isEmpty else { store.error = "Let the number picker settle before completing the set."; return }
            if let inputError { store.error = inputError; return }
        }
        _ = store.performFocused(command, sessionID: sessionID, expectedSet: expectedSet, now: now)
        if [.skipSet, .undo, .finish].contains(command) { inputErrors = [:] }
        scheduleRest()
    }
    func togglePause() {
        if session?.status == .paused { store.resume(now: now) } else { store.pause(now: now) }
        scheduleRest()
    }
    func rejectInput(_ field: WorkoutInputField, message: String) { inputErrors[field] = message }
    func editSet(_ value: WorkoutSet, field: WorkoutInputField? = nil) {
        guard let current, value.id == current.set.id, current.set.status == .pending else { return }
        guard value.isValid else { if let field { inputErrors[field] = "Check \(field.rawValue). Enter a finite value within the supported range." }; return }
        if let field { inputErrors[field] = nil }
        store.update(at: now) { session in
            if let e = session.entries.firstIndex(where: { $0.id == current.entry.id }), let s = session.entries[e].sets.firstIndex(where: { $0.id == value.id }) {
                session.entries[e].sets[s] = value
            }
        }
    }
    private func scheduleRest() {
        let deadline = visible && session?.status == .inProgress && phase == .resting ? session?.restUntil : nil
        guard deadline != scheduledDeadline else { return }
        restTask?.cancel(); restTask = nil; scheduledDeadline = deadline
        guard let deadline else { return }
        let delay = max(0, deadline.timeIntervalSince(now))
        restTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled, let self, self.visible, self.session?.restUntil == deadline, self.phase == .resting else { return }
            self.scheduledDeadline = nil
            self.refresh()
        }
    }
}

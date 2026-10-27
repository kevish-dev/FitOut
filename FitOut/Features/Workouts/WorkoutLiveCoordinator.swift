import Foundation
import ActivityKit
import Observation
import UIKit
import SwiftUI

@MainActor enum WorkoutRuntime {
    private static var cached: AppContainer?
    static var presentation: WorkoutPresentationCoordinator? { cached?.workoutPresentation }
    static func shared() throws -> AppContainer {
        if let cached { return cached }
        let container = try AppContainer.live(); cached = container
        return container
    }
    static func perform(operation: String, sessionID: UUID, commandID: UUID) async throws {
        let container = try shared()
        let succeeded = container.workouts.runQuickAction(operation, sessionID: sessionID, commandID: commandID)
        container.workoutPresentation.changed()
        await container.workoutPresentation.flush()
        // Complete rest alarm cancellation/replacement before a locked-screen
        // Live Activity action returns control to iOS.
        await container.workoutHaptics.flushAlerts()
        guard succeeded else { throw WorkoutLiveActionError.unavailable(container.workouts.error ?? "Open FitOut to update this workout.") }
    }
}

@MainActor @Observable final class WorkoutPresentationCoordinator {
    private let store: WorkoutStore
    private let profile: ProfileStore
    private let defaults: UserDefaults
    private let enabled: Bool
    private let floating: WorkoutFloatingController
    private var pending: Request?
    private var syncTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var watchedActivityID: String?
    private var selfEndedIDs: Set<String> = []
    private(set) var liveActivityMessage: String?
    private struct Request { var session: WorkoutSession?; var unit: WeightUnit; var allowStart: Bool }

    init(store: WorkoutStore, gym: GymStore, profile: ProfileStore, defaults: UserDefaults, enabled: Bool, haptics: HapticService? = nil) {
        self.store = store; self.profile = profile; self.defaults = defaults; self.enabled = enabled
        floating = WorkoutFloatingController(store: store, gym: gym, profile: profile, defaults: defaults, haptics: haptics)
    }
    func changed() {
        guard enabled else { return }
        floating.refresh()
        pending = Request(session: store.active, unit: profile.draft.weightUnit, allowStart: UIApplication.shared.applicationState == .active)
        guard syncTask == nil else { return }
        syncTask = Task { [weak self] in
            guard let self else { return }
            while let request = self.pending {
                self.pending = nil
                await self.synchronize(request)
            }
            self.syncTask = nil
        }
    }
    func sceneChanged(active: Bool) {
        guard enabled else { return }
        floating.sceneChanged(active: active)
        if active {
            if let deadline = store.active?.restUntil, store.active?.status == .inProgress, deadline <= .now { store.endRest() }
            changed()
        }
    }
    func flush() async { await syncTask?.value }
    func appearanceChanged(_ scheme: ColorScheme?) { floating.setAppearance(scheme) }
    func overlayChanged() { if enabled { floating.refresh() } }
    func protectWorkoutControl(_ id: String, frame: CGRect?) { if enabled { floating.protect(id, frame: frame) } }
    @discardableResult func openCurrentWorkout() -> Bool {
        guard enabled, store.active != nil else { return false }
        floating.sceneChanged(active: true)
        return floating.open()
    }
    func showLiveActivity() {
        if let id = store.active?.id { defaults.removeObject(forKey: "workout.live.dismissed." + id.uuidString) }
        changed()
    }
    private func synchronize(_ request: Request) async {
        let activities = Activity<WorkoutLiveAttributes>.activities
        guard let session = request.session else {
            for activity in activities { selfEndedIDs.insert(activity.id); await Self.endActivity(activity.id) }
            liveActivityMessage = nil; return
        }
        for activity in activities where activity.attributes.sessionID != session.id { selfEndedIDs.insert(activity.id); await Self.endActivity(activity.id) }
        let state = Self.content(for: session, unit: request.unit)
        let content = ActivityContent(state: state, staleDate: state.paused ? nil : state.restUntil)
        let matching = activities.filter { $0.attributes.sessionID == session.id && [.active, .stale].contains($0.activityState) }
        if let activity = matching.first {
            for duplicate in matching.dropFirst() { selfEndedIDs.insert(duplicate.id); await Self.endActivity(duplicate.id) }
            await Self.updateActivity(activity.id, content: content)
            watch(activity); liveActivityMessage = nil
            return
        }
        guard request.allowStart else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivityMessage = "Live Activities are turned off in iPhone settings. Your workout keeps recording in FitOut."
            return
        }
        guard !defaults.bool(forKey: "workout.live.dismissed." + session.id.uuidString) else {
            liveActivityMessage = "Live Activity dismissed. You can show it again for this workout."
            return
        }
        do {
            let activity = try Activity.request(attributes: WorkoutLiveAttributes(sessionID: session.id), content: content, pushType: nil)
            watch(activity); liveActivityMessage = nil
        } catch { liveActivityMessage = "Live Activity could not start. Your workout keeps recording in FitOut." }
    }
    // ActivityKit's handle is not Sendable. Resolve a fresh handle in the async
    // executor instead of sending one shared with the main-actor observer.
    nonisolated private static func endActivity(_ id: String) async {
        guard let activity = Activity<WorkoutLiveAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }
    nonisolated private static func updateActivity(_ id: String, content: ActivityContent<WorkoutLiveAttributes.ContentState>) async {
        guard let activity = Activity<WorkoutLiveAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }
    private func watch(_ activity: Activity<WorkoutLiveAttributes>) {
        guard watchedActivityID != activity.id else { return }
        watchedActivityID = activity.id; watchTask?.cancel()
        watchTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if state == .dismissed, self?.selfEndedIDs.contains(activity.id) != true {
                    self?.defaults.set(true, forKey: "workout.live.dismissed." + activity.attributes.sessionID.uuidString)
                    self?.liveActivityMessage = "Live Activity dismissed. You can show it again for this workout."
                }
            }
        }
    }
    static func content(for session: WorkoutSession, unit: WeightUnit, now: Date = .now) -> WorkoutLiveAttributes.ContentState {
        let unit = session.execution?.preferredUnit ?? unit
        func bounded(_ text: String) -> String {
            // Whole-character truncation avoids broken emoji/replacement characters.
            var result = ""
            for character in text.split(whereSeparator: \.isWhitespace).joined(separator: " ") {
                guard result.utf8.count + String(character).utf8.count <= 160 else { break }
                result.append(character)
            }
            return result
        }
        let resting = session.execution?.phase == .resting || session.execution?.resumePhase == .resting || session.restUntil != nil
        let next = session.pendingWork.first
        let upcoming: (entry: WorkoutEntry, set: WorkoutSet)? = next.flatMap { reference in
            guard let entry = session.entries.first(where: { $0.id == reference.entryID }),
                  let set = entry.sets.first(where: { $0.id == reference.setID }) else { return nil }
            return (entry, set)
        }
        let focus = resting ? upcoming : session.focusedWork
        func values(_ set: WorkoutSet, kind: ExerciseKind) -> String {
            if kind == .duration { return "\(set.seconds.formatted()) sec" }
            return "\(set.reps) reps" + (kind == .weighted ? " · \(unit.display(set.loadKG).formatted()) \(unit.rawValue)" : "")
        }
        let completed = session.entries.flatMap { entry in entry.sets.filter { $0.completedAt != nil }.map { (entry.exercise, $0) } }
            .max { ($0.1.completedAt ?? .distantPast) < ($1.1.completedAt ?? .distantPast) }
        let setElapsed = resting ? nil : focus.flatMap { session.setElapsed($0.set, at: now) }
        let setRunning = !resting && focus?.set.startedAt != nil && focus?.set.timedActiveSeconds == nil && session.status == .inProgress
        let entries = session.entries.filter { !$0.skipped }
        let phase = session.execution?.phase ?? (!session.isActive ? .workoutCompleted : session.status == .paused ? .paused : resting ? .resting : setRunning ? .activeSet : .ready)
        return WorkoutLiveAttributes.ContentState(revision: session.telemetry?.revision ?? session.id,
            title: bounded(session.title), exercise: bounded(focus?.entry.exercise.name ?? (session.entries.isEmpty ? "Choose exercises in FitOut" : "All remaining sets logged")),
            target: bounded(focus.map { work in "Set \((work.entry.sets.firstIndex { $0.id == work.set.id } ?? 0) + 1)/\(work.entry.sets.count) · " + values(work.set, kind: work.entry.exercise.kind) } ?? ""),
            lastSet: bounded(completed.map { $0.0.name + " · " + values($0.1, kind: $0.0.kind) } ?? ""),
            clockStart: session.startedAt.addingTimeInterval(session.pausedSeconds), paused: session.status == .paused,
            elapsed: session.duration(at: now), loggedSets: session.completedSets.count, totalSets: session.trackedSetCount,
            laps: 0, lastLap: nil,
            setTimerStart: setRunning ? setElapsed.map { now.addingTimeInterval(-$0) } : nil, setTimerElapsed: setElapsed,
            restUntil: session.restUntil, pausedRest: session.restRemaining(at: now), phase: phase.rawValue, skippedSets: session.skippedSets.count,
            exerciseIndex: focus.flatMap { work in entries.firstIndex { $0.id == work.entry.id }.map { $0 + 1 } },
            exerciseCount: entries.count, setIndex: focus.flatMap { work in work.entry.sets.firstIndex { $0.id == work.set.id }.map { $0 + 1 } },
            exerciseSetCount: focus?.entry.sets.count, prescription: focus.map { bounded(values($0.set, kind: $0.entry.exercise.kind)) },
            restStartedAt: resting ? completed?.1.completedAt : nil)
    }
}

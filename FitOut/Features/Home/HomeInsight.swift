import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct HomeWorkoutInsight: Equatable, Sendable {
    let exerciseID: String
    let text: String
    // Only numeric facts and app-authored categories go to the model. Exercise
    // names, notes, profile information, and raw workout logs are not prompts.
    let evidence: String
    let sourceSessions: [UUID]
}

struct HomeInsightRequest: Equatable, Sendable {
    let isAvailable: Bool
    let candidates: [HomeWorkoutInsight]
}

enum HomeInsightPolicy {
    static func candidates(sessions: [WorkoutSession], routine: Routine?, unit: WeightUnit,
                           now: Date = .now, calendar: Calendar = .current) -> [HomeWorkoutInsight] {
        guard let routine, routine.isActive, routine.validationMessage == nil,
              let cutoff = calendar.date(byAdding: .day, value: -42, to: now),
              let freshAfter = calendar.date(byAdding: .day, value: -7, to: now) else { return [] }
        // This insight policy currently supports uniform legacy targets only.
        // Independently configured sets need a matching evidence policy first.
        let plans = Dictionary(grouping: routine.days.filter { $0.kind == .workout }.flatMap(\.exercises), by: \.exerciseID)
        let recent = sessions.filter {
            $0.status == .completed && $0.routineID == routine.id &&
            $0.startedAt >= max(cutoff, routine.updatedAt) && $0.startedAt <= now &&
            ($0.endedAt ?? $0.startedAt) <= now
        }.sorted { $0.startedAt > $1.startedAt }

        var result: [HomeWorkoutInsight] = []
        for exerciseID in plans.keys.sorted() {
            guard let variants = plans[exerciseID], let plan = variants.first,
                  variants.allSatisfy({ $0.setTargets == nil && $0.sets == plan.sets && $0.repMin == plan.repMin &&
                      $0.repMax == plan.repMax && $0.loadKG == plan.loadKG }) else { continue }

            // Use the latest three occurrences, not a cherry-picked subset of
            // successful sessions. Multiple workouts on one day count once.
            var seenDays = Set<Date>()
            let occurrences = recent.filter { session in
                guard session.entries.contains(where: { $0.exercise.id == exerciseID }) else { return false }
                return seenDays.insert(calendar.startOfDay(for: session.startedAt)).inserted
            }
            let sample = Array(occurrences.prefix(3))
            guard sample.count == 3, let latest = sample.first, let oldest = sample.last,
                  latest.startedAt >= freshAfter,
                  (calendar.dateComponents([.day], from: oldest.startedAt, to: latest.startedAt).day ?? 0) >= 7 else { continue }

            let entries = sample.compactMap { session -> WorkoutEntry? in
                let matches = session.entries.filter { $0.exercise.id == exerciseID }
                guard matches.count == 1, let entry = matches.first,
                      !entry.skipped, entry.exercise.kind == .weighted else { return nil }
                return entry
            }
            guard entries.count == 3 else { continue }
            let workingSets = entries.map { $0.sets.filter { $0.type == .working } }
            guard workingSets.allSatisfy({ sets in
                sets.count == plan.sets && sets.allSatisfy {
                    $0.isValid && $0.reps > 0 && $0.loadKG > 0 &&
                    $0.completedAt.map { $0 <= now } == true && $0.rpe != nil
                }
            }), let load = workingSets.first?.first?.loadKG,
               workingSets.flatMap({ $0 }).allSatisfy({ abs($0.loadKG - load) < 0.01 }),
               plan.loadKG.map({ abs($0 - load) < 0.01 }) ?? true else { continue }

            let name = String(entries[0].exercise.name.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(48))
            guard !name.isEmpty else { continue }
            let displayedLoad = unit.display(load).formatted(.number.precision(.fractionLength(0...1)))
            let allSets = workingSets.flatMap { $0 }
            let text: String
            let evidence: String
            if allSets.allSatisfy({ $0.reps >= plan.repMax && ($0.rpe ?? 10) <= 8 }) {
                let sets = plan.sets == 1 ? "the working set" : "all \(plan.sets) sets"
                let reps = plan.repMax == 1 ? "1 rep" : "\(plan.repMax) reps"
                text = "\(name): \(sets) reached \(reps) at \(displayedLoad) \(unit.rawValue) in three workouts with effort ≤8/10. Review the planned load."
                evidence = "Rep ceiling met in 3 workouts spanning at least 7 days; \(plan.sets) working sets per workout; every set at least \(plan.repMax) reps; same load; every logged effort at most 8/10. Action: review planned load."
            } else if workingSets.allSatisfy({ sets in
                sets.contains { $0.reps < plan.repMin && ($0.rpe ?? 0) >= 9 }
            }) {
                text = "\(name) fell below your \(plan.repMin)-rep target at \(displayedLoad) \(unit.rawValue) with effort ≥9/10 in three workouts. Review the planned load."
                evidence = "Rep shortfall in 3 workouts spanning at least 7 days; at least one working set per workout below \(plan.repMin) reps with logged effort at least 9/10; same load. Action: review planned load."
            } else { continue }
            result.append(HomeWorkoutInsight(exerciseID: exerciseID, text: text, evidence: evidence,
                                             sourceSessions: sample.map(\.id)))
        }
        return Array(result.prefix(3))
    }

    static func selectedIndex(_ response: String, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let value = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return (0..<count).first { value == "C\($0)" }
    }
}

@MainActor protocol HomeInsightSelecting {
    func select(from candidates: [HomeWorkoutInsight]) async throws -> Int?
}

@MainActor struct OnDeviceHomeInsightSelector: HomeInsightSelecting {
    func select(from candidates: [HomeWorkoutInsight]) async throws -> Int? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: """
                Select one useful workout insight from the supplied repeated evidence.
                Choose only when reviewing the current planned load is actionable.
                Do not infer recovery, illness, injury, or strength changes. Do not add advice.
                Reply with exactly one candidate ID (C0, C1, or C2), or NONE if none is useful.
                """
            )
            let prompt = candidates.enumerated().map { "C\($0.offset): \($0.element.evidence)" }.joined(separator: "\n")
            let response = try await session.respond(to: prompt, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 8))
            return HomeInsightPolicy.selectedIndex(response.content, count: candidates.count)
        }
        #endif
        return nil
    }
}

enum HomeInsightEngine {
    @MainActor static func insight(for request: HomeInsightRequest,
                                  selector: any HomeInsightSelecting = OnDeviceHomeInsightSelector()) async -> HomeWorkoutInsight? {
        guard request.isAvailable, !request.candidates.isEmpty, !Task.isCancelled else { return nil }
        do {
            guard let index = try await selector.select(from: request.candidates),
                  !Task.isCancelled, request.candidates.indices.contains(index) else { return nil }
            // The model selects an evidence-backed statement; arbitrary model
            // prose is never displayed and there is no generic fallback.
            return request.candidates[index]
        } catch { return nil }
    }
}

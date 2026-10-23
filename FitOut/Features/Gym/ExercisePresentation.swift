import Foundation

enum ExerciseCategory: String, CaseIterable, Identifiable {
    case strength = "Strength", bodyweight = "Bodyweight", cardio = "Cardio", mobility = "Mobility & stretching"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .strength: "dumbbell"
        case .bodyweight: "figure.strengthtraining.functional"
        case .cardio: "figure.run"
        case .mobility: "figure.flexibility"
        }
    }
}

enum ExerciseEquipment: String, CaseIterable, Identifiable {
    case noEquipment = "No equipment", barbell = "Barbell", dumbbell = "Dumbbells", kettlebell = "Kettlebell"
    case cable = "Cable", machine = "Machine", band = "Resistance band", other = "Other equipment"
    var id: String { rawValue }
}

extension ExerciseDefinition {
    var category: ExerciseCategory {
        if pattern == "Cardio" || pattern == "Conditioning" { return .cardio }
        if pattern == "Mobility" || pattern == "Stretch" { return .mobility }
        if equipmentFilters.contains(.band) { return .strength }
        if kind == .bodyweight || (kind == .duration && equipment == "None") { return .bodyweight }
        return .strength
    }
    var equipmentFilters: Set<ExerciseEquipment> {
        let text = equipment.lowercased()
        if text == "none" || text.isEmpty { return [.noEquipment] }
        var values = Set<ExerciseEquipment>()
        if text.contains("barbell") || text.contains("ez bar") || text.contains("trap bar") { values.insert(.barbell) }
        if text.contains("dumbbell") { values.insert(.dumbbell) }
        if text.contains("kettlebell") { values.insert(.kettlebell) }
        if text.contains("cable") { values.insert(.cable) }
        if text.contains("machine") || ["treadmill", "exercise bike", "rowing ergometer"].contains(text) { values.insert(.machine) }
        if text.contains("resistance band") { values.insert(.band) }
        return values.isEmpty ? [.other] : values
    }
    var trackingTitle: String {
        switch kind {
        case .weighted: "Weight & reps"
        case .bodyweight: "Reps"
        case .duration: "Time & optional distance"
        }
    }
    // Artwork belongs to the app bundle, never to a user's exercise record.
    var imageAssetName: String? {
        guard !isCustom, ExerciseCatalogue.byID[id] != nil else { return nil }
        return "exercise-" + id
    }
}

/// Shared by the library and every exercise picker so their filters behave identically.
struct ExerciseFilter {
    var search = ""
    var muscles: [Muscle] = []
    var favoritesOnly = false
    var category: ExerciseCategory?
    var equipment: ExerciseEquipment?

    func matches(_ exercise: ExerciseDefinition) -> Bool {
        if favoritesOnly && !exercise.isFavorite { return false }
        if let category, exercise.category != category { return false }
        if let equipment, !exercise.equipmentFilters.contains(equipment) { return false }
        if !muscles.isEmpty && Set(exercise.muscles + exercise.secondary).isDisjoint(with: muscles) { return false }
        let targets = exercise.muscles + exercise.secondary
        let legMuscles: Set<Muscle> = [.quadriceps, .hamstrings, .glutes, .calves]
        let tags = [exercise.name, exercise.aliases, exercise.equipment, exercise.pattern, exercise.category.rawValue,
                    targets.map(\.title).joined(separator: " "),
                    targets.contains(.abdominals) || targets.contains(.obliques) ? "core abs" : "",
                    !Set(targets).isDisjoint(with: legMuscles) ? "legs lower body" : ""]
            .joined(separator: " ")
        let normalized = Self.normalize(tags)
        let words = Self.normalize(search).split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { normalized.contains($0) }
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "/", with: " ")
    }
}

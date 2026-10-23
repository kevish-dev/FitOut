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

enum ExerciseLibraryScope: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites", custom = "My exercises"
    var id: Self { self }
}

enum ExerciseSortOrder: String, CaseIterable, Identifiable {
    case nameAscending = "Name: A–Z", nameDescending = "Name: Z–A", muscle = "Muscle group", equipment = "Equipment"
    var id: Self { self }
    var shortTitle: String {
        switch self { case .nameAscending: "A–Z"; case .nameDescending: "Z–A"; case .muscle: "Muscle"; case .equipment: "Equipment" }
    }
    func sorted(_ exercises: [ExerciseDefinition]) -> [ExerciseDefinition] {
        func compare(_ left: String, _ right: String) -> ComparisonResult {
            left.compare(right, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
        }
        return exercises.sorted { left, right in
            let primary: ComparisonResult
            switch self {
            case .nameAscending: primary = compare(left.name, right.name)
            case .nameDescending: primary = compare(right.name, left.name)
            case .muscle: primary = compare(left.muscles.first?.title ?? "", right.muscles.first?.title ?? "")
            case .equipment: primary = compare(left.equipment, right.equipment)
            }
            if primary != .orderedSame { return primary == .orderedAscending }
            let name = compare(left.name, right.name)
            return name == .orderedSame ? left.id < right.id : name == .orderedAscending
        }
    }
}

struct ExerciseBrowseFilters: Equatable {
    var muscles: [Muscle] = []
    var category: ExerciseCategory?
    var equipment: ExerciseEquipment?
    var count: Int { muscles.count + (category == nil ? 0 : 1) + (equipment == nil ? 0 : 1) }
}

struct ExerciseLibraryQuery {
    var search = ""
    var scope: ExerciseLibraryScope = .all
    var filters = ExerciseBrowseFilters()
    var sort: ExerciseSortOrder = .nameAscending

    func results(in exercises: [ExerciseDefinition]) -> [ExerciseDefinition] {
        let filter = ExerciseFilter(search: search, muscles: filters.muscles, favoritesOnly: scope == .favorites,
                                    category: filters.category, equipment: filters.equipment)
        return sort.sorted(exercises.filter { filter.matches($0) && (scope != .custom || $0.isCustom) })
    }
}

/// Search, filters and sorting never change the order in which movements are added.
struct ExercisePickerSelection {
    private(set) var ids: [String] = []
    mutating func add(_ id: String) { if !ids.contains(id) { ids.append(id) } }
    mutating func remove(_ id: String) { ids.removeAll { $0 == id } }
    mutating func toggle(_ id: String) { if ids.contains(id) { remove(id) } else { add(id) } }
    mutating func clear() { ids = [] }
    mutating func retainAvailable(_ available: Set<String>) { ids.removeAll { !available.contains($0) } }
    func exercises(in catalogue: [ExerciseDefinition]) -> [ExerciseDefinition] {
        let byID = Dictionary(catalogue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }
}

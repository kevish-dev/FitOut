import Foundation

enum Gender: String, Codable, CaseIterable {
    case male = "Male", female = "Female"
}

enum WeightUnit: String, Codable, CaseIterable {
    case kg, lbs
    var multiplier: Double { self == .kg ? 1 : 2.2046226218 }
    func display(_ kilograms: Double) -> Double { kilograms * multiplier }
    func kilograms(_ value: Double) -> Double { value / multiplier }
    var range: ClosedRange<Int> { self == .kg ? 25...250 : 55...551 }
}

enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case muscle, strength, endurance, fatLoss, mobility, shape, health, recovery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .muscle: "Build Muscle"
        case .strength: "Gain Strength"
        case .endurance: "Improve Endurance"
        case .fatLoss: "Lose Fat"
        case .mobility: "Increase Flexibility & Mobility"
        case .shape: "Maintain Shape"
        case .health: "General Health"
        case .recovery: "Rehab / Recovery"
        }
    }
    var symbol: String {
        switch self {
        case .muscle: "dumbbell.fill"
        case .strength: "chart.bar.fill"
        case .endurance: "figure.run"
        case .fatLoss: "flame"
        case .mobility: "figure.flexibility"
        case .shape: "figure.stand"
        case .health: "heart.fill"
        case .recovery: "arrow.triangle.2.circlepath"
        }
    }
}

struct FitnessProfile: Codable, Equatable {
    var name = ""
    var emoji = "💪"
    var photoData: Data?
    var usesPhoto = false
    var gender: Gender = .male
    var age = 20
    // Always store kilograms; changing display units never changes the original value.
    var currentWeightKG = 62.0
    var targetWeightKG = 65.0
    var unit: WeightUnit = .kg
    var goals: Set<FitnessGoal> = [.muscle, .health]
    var completedAt: Date?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isNameValid: Bool { !trimmedName.isEmpty && trimmedName.count <= 40 }
    var canComplete: Bool {
        isNameValid && (13...100).contains(age)
        && (24.9...250.1).contains(currentWeightKG)
        && (24.9...250.1).contains(targetWeightKG) && !goals.isEmpty
    }
}

struct OnboardingSnapshot: Codable {
    var profile = FitnessProfile()
    var step = 0
}

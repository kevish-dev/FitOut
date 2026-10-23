import Foundation

enum PrimaryGoal: String, Codable, CaseIterable, Identifiable {
    case muscle = "Build muscle", fatLoss = "Lose fat", recomposition = "Body recomposition", strength = "Strength", endurance = "Endurance", fitness = "General fitness"
    var id: String { rawValue }
}
enum HeightUnit: String, Codable, CaseIterable { case cm, feet = "ft/in" }

struct ProfileData: Equatable {
    var name = ""
    var age = 20
    var gender: Gender?
    var heightCM = 170.0
    var currentWeightKG = 62.0
    var targetWeightKG: Double?
    var weightUnit: WeightUnit = .kg
    var heightUnit: HeightUnit = .cm
    var primaryGoal: PrimaryGoal?
    var emoji = "💪"
    var avatarData: Data?
    var completedAt: Date?
    var step = 0
    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var validationMessage: String? {
        if trimmedName.isEmpty || trimmedName.count > 40 { return "Enter a name with 1–40 characters." }
        if !(13...100).contains(age) { return "Age must be between 13 and 100." }
        if !heightCM.isFinite || !(80...250).contains(heightCM) { return "Height must be between 80 and 250 cm." }
        if !currentWeightKG.isFinite || !(25...350).contains(currentWeightKG) { return "Current weight must be between 25 and 350 kg." }
        if let targetWeightKG, !targetWeightKG.isFinite || !(25...350).contains(targetWeightKG) { return "Target weight must be between 25 and 350 kg, or leave it blank." }
        if primaryGoal == nil { return "Choose one primary fitness goal." }
        return nil
    }
    static func centimeters(feet: Int, inches: Double) -> Double { (Double(feet) * 12 + inches) * 2.54 }
    static func feetAndInches(_ centimeters: Double) -> (feet: Int, inches: Double) {
        let inches = centimeters / 2.54
        return (Int(inches / 12), inches.truncatingRemainder(dividingBy: 12))
    }
}

import SwiftUI

enum NutritionUI {
    static func value(_ value: Double?, unit: String = "", decimals: Int = 0) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...decimals))) + (unit.isEmpty ? "" : " " + unit)
    }
}

struct NutritionNumberField: View {
    let title: String
    @Binding var value: Double?
    var body: some View {
        LabeledContent(title) {
            TextField("Not supplied", value: $value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 84)
                .accessibilityLabel(title)
        }
    }
}
struct NutritionValueFields: View {
    @Binding var values: NutritionValues
    var expanded = true
    var body: some View {
        ForEach(expanded ? NutritionNutrient.allCases : [.calories, .protein, .carbohydrates, .fat]) { key in
            NutritionNumberField(title: "\(key.title) (\(key.unit))", value: Binding(get: { values[key] }, set: { values[key] = $0 }))
        }
    }
}
struct NutritionValuesList: View {
    let values: NutritionValues
    var incomplete: [NutritionNutrient] = []
    var body: some View {
        ForEach(NutritionNutrient.allCases) { key in
            LabeledContent {
                Text(NutritionUI.value(values[key], unit: key.unit, decimals: key == .calories ? 0 : 1) + (incomplete.contains(key) && values[key] != nil ? " · partial" : ""))
                    .foregroundStyle(values[key] == nil ? FitTheme.textSecondary : .white)
            } label: { Text(key.title) }
        }
    }
}
struct NutritionFoodRow: View {
    let food: NutritionFood
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: food.source == .recipe ? "book.closed" : "fork.knife")
                .font(.system(size: 18)).foregroundStyle(FitTheme.dashboardAccent)
                .frame(width: 42, height: 48).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(food.name).font(FitTheme.section(15)).foregroundStyle(.white)
                Text("\(food.baseQuantity.formatted()) \(food.baseUnit.rawValue) · \(food.sourceTitle)")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                Text("P \(NutritionUI.value(food.values.protein, decimals: 1)) · C \(NutritionUI.value(food.values.carbohydrates, decimals: 1)) · F \(NutritionUI.value(food.values.fat, decimals: 1)) g")
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            Spacer(minLength: 4)
            Text(NutritionUI.value(food.values.calories)).font(FitTheme.section(15)).foregroundStyle(.white)
        }.padding(.vertical, 5)
    }
}
struct NutritionPrimaryButton: View {
    let title: String
    var symbol = "plus"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(FitTheme.button(15)).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white).background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
extension View {
    func nutritionForm() -> some View {
        self.font(FitTheme.body(14)).foregroundStyle(.white).tint(FitTheme.dashboardAccent)
            .scrollContentBackground(.hidden).background(FitTheme.dashboardBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
    }
}

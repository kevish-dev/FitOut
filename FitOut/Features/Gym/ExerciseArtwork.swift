import SwiftUI
import UIKit

struct ExerciseArtwork: View {
    let exercise: ExerciseDefinition?
    var size: CGFloat = 56
    var expanded = false

    private var artwork: UIImage? {
        exercise?.imageAssetName.flatMap { UIImage(named: $0) }
    }
    var body: some View {
        ZStack {
            FitTheme.surface
            if let artwork {
                Image(uiImage: artwork).resizable().scaledToFit().padding(expanded ? 16 : 4)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: exercise?.category.symbol ?? "dumbbell")
                        .font(.system(size: expanded ? 48 : 22, weight: .regular))
                        .foregroundStyle(FitTheme.dashboardAccent)
                    if expanded {
                        Text(exercise?.isCustom == true ? "Custom exercise" : "Exercise image coming soon").font(FitTheme.medium(13))
                            .foregroundStyle(FitTheme.textSecondary)
                    }
                }
            }
        }
        .frame(width: expanded ? nil : size, height: expanded ? 250 : size)
        .frame(maxWidth: expanded ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 20 : 12))
        .overlay { RoundedRectangle(cornerRadius: expanded ? 20 : 12).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
        .accessibilityHidden(!expanded)
        .accessibilityLabel(artwork == nil ? "Exercise image not yet available" : "\(exercise?.name ?? "Exercise") reference image")
    }
}

struct ExerciseLibraryRow: View {
    let exercise: ExerciseDefinition
    var body: some View {
        HStack(spacing: 12) {
            ExerciseArtwork(exercise: exercise)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(exercise.name).font(FitTheme.section(15)).foregroundStyle(.primary)
                    if exercise.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(FitTheme.dashboardAccent) }
                }
                Text(exercise.muscles.map(\.title).joined(separator: ", "))
                    .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                Text(exercise.equipment == "None" ? "No equipment" : exercise.equipment)
                    .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 4)
    }
}

struct ExerciseFilterControls: View {
    @Binding var category: ExerciseCategory?
    @Binding var equipment: ExerciseEquipment?
    var body: some View {
        Picker("Type", selection: $category) {
            Text("All types").tag(nil as ExerciseCategory?)
            ForEach(ExerciseCategory.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
        Picker("Equipment", selection: $equipment) {
            Text("All equipment").tag(nil as ExerciseEquipment?)
            ForEach(ExerciseEquipment.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }
    }
}

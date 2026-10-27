import SwiftUI

struct ExerciseFilterSheet: View {
    let query: ExerciseLibraryQuery
    let exercises: [ExerciseDefinition]
    let apply: (ExerciseBrowseFilters) -> Void
    @State private var draft: ExerciseBrowseFilters
    @State private var showMap = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(query: ExerciseLibraryQuery, exercises: [ExerciseDefinition], apply: @escaping (ExerciseBrowseFilters) -> Void) {
        self.query = query; self.exercises = exercises; self.apply = apply
        _draft = State(initialValue: query.filters)
    }
    private var count: Int {
        var preview = query; preview.filters = draft
        return preview.results(in: exercises).count
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        headingLayout {
                            Label("Muscles", systemImage: "figure.arms.open").font(FitTheme.section(17))
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Button { showMap = true } label: { Text("Use muscle map").font(FitTheme.medium(12)).frame(minHeight: 44).contentShape(Rectangle()) }
                        }
                        Text("Choose any. Primary and secondary muscles are included.")
                            .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 120), spacing: 8)], spacing: 8) {
                            ForEach(Muscle.allCases) { muscle in
                                ExerciseChoiceChip(title: muscle.title, selected: draft.muscles.contains(muscle)) {
                                    if draft.muscles.contains(muscle) { draft.muscles.removeAll { $0 == muscle } }
                                    else { draft.muscles.append(muscle) }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Equipment", systemImage: "dumbbell").font(FitTheme.section(17))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 120), spacing: 8)], spacing: 8) {
                            ExerciseChoiceChip(title: "Any equipment", selected: draft.equipment == nil) { draft.equipment = nil }
                            ForEach(ExerciseEquipment.allCases) { equipment in
                                ExerciseChoiceChip(title: equipment.rawValue, selected: draft.equipment == equipment) {
                                    draft.equipment = draft.equipment == equipment ? nil : equipment
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Exercise type", systemImage: "square.grid.2x2").font(FitTheme.section(17))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), spacing: 8)], spacing: 8) {
                            ExerciseChoiceChip(title: "All types", selected: draft.category == nil) { draft.category = nil }
                            ForEach(ExerciseCategory.allCases) { category in
                                ExerciseChoiceChip(title: category.rawValue, symbol: category.symbol, selected: draft.category == category) {
                                    draft.category = draft.category == category ? nil : category
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
            }
            .background(FitTheme.dashboardBackground)
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Reset") { draft = ExerciseBrowseFilters() }.disabled(draft.count == 0) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { apply(draft); dismiss() } label: {
                    Text("Show \(count) \(count == 1 ? "exercise" : "exercises")")
                        .font(FitTheme.button(16)).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white)
                .background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier("applyExerciseFilters")
                .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity).background(.bar)
                .workoutControlClearance("exercise.filter.actions")
            }
            .sheet(isPresented: $showMap) {
                NavigationStack {
                    MuscleMapView(selection: $draft.muscles)
                        .toolbar { Button("Done") { showMap = false } }
                }
            }
        }.tint(FitTheme.dashboardAccent).foregroundStyle(FitTheme.textPrimary)
            .presentationDragIndicator(.visible).presentationCornerRadius(28)
    }
    private var headingLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
    }
}

struct ExerciseChoiceChip: View {
    let title: String
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .medium)) }
                Text(title).font(FitTheme.medium(12)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? FitTheme.dashboardAccent : FitTheme.textSecondary)
            .background(selected ? FitTheme.dashboardAccent.opacity(0.1) : FitTheme.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? FitTheme.dashboardAccent.opacity(0.65) : FitTheme.subtleBorder, lineWidth: 1) }
            .animation(FitMotion.change(reduceMotion: reduceMotion), value: selected)
        }
        .buttonStyle(RoutineEditorPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

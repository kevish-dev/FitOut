import SwiftUI

enum ExerciseBrowserMode: Equatable { case browse, single, multiple }

struct ExerciseBrowser: View {
    @Bindable var store: GymStore
    let title: String
    var mode: ExerciseBrowserMode = .browse
    var selectionHint: String? = nil
    var previousPerformance: ((ExerciseDefinition) -> String?)? = nil
    var onSelect: (([ExerciseDefinition]) -> Void)? = nil
    @State private var query = ExerciseLibraryQuery()
    @State private var selection = ExercisePickerSelection()
    @State private var showFilters = false
    @State private var reviewSelection = false
    @State private var custom: ExerciseDefinition?
    @State private var created: ExerciseDefinition?
    @State private var inspecting: ExerciseDefinition?
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var filtered: [ExerciseDefinition] { query.results(in: store.exercises) }
    private var chosen: [ExerciseDefinition] { selection.exercises(in: store.exercises) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if query.filters.count > 0 { activeFilters }
                HStack {
                    Text("\(filtered.count) \(filtered.count == 1 ? "exercise" : "exercises")").font(FitTheme.section(15))
                    Spacer()
                    Text(query.sort.rawValue).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }.padding(.vertical, 5)
                if let selectionHint {
                    Text(selectionHint)
                        .font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary).padding(.bottom, 4)
                }
                ForEach(filtered) { exercise in exerciseCard(exercise) }
                if filtered.isEmpty { emptyState }
                if let error = store.error { Label(error, systemImage: "exclamationmark.circle").font(FitTheme.body(13)).foregroundStyle(.orange) }
            }
            .frame(maxWidth: 560).padding(FitTheme.pageInset).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively).scrollBounceBehavior(.basedOnSize)
        .background(FitTheme.dashboardBackground)
        .safeAreaInset(edge: .top, spacing: 0) { controls }
        .safeAreaInset(edge: .bottom, spacing: 0) { if mode == .multiple { selectionFooter.workoutControlClearance("exercise.selection.actions") } }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .tint(FitTheme.dashboardAccent).foregroundStyle(FitTheme.textPrimary)
        .toolbar {
            if mode != .browse { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New exercise", systemImage: "plus") { createExercise() }
                    .accessibilityIdentifier("newLibraryExercise")
            }
        }
        .sheet(isPresented: $showFilters) {
            ExerciseFilterSheet(query: query, exercises: store.exercises) { query.filters = $0 }
        }
        .sheet(item: $inspecting) { exercise in
            NavigationStack {
                ExerciseDetail(store: store, exerciseID: exercise.id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { inspecting = nil } } }
            }
        }
        .sheet(item: $custom, onDismiss: {
            if mode == .single, let created { searchFocused = false; onSelect?([created]) }
            created = nil
        }) { exercise in
            CustomExerciseEditor(store: store, exercise: exercise) { saved in
                if mode == .multiple { selection.add(saved.id) }
                else if mode == .single { created = saved }
            }
        }
        .onChange(of: store.exercises.map(\.id)) { _, ids in selection.retainAvailable(Set(ids)) }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(FitTheme.textSecondary)
                    TextField("Name, muscle or equipment", text: $query.search)
                        .font(FitTheme.body(14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                        .accessibilityIdentifier("exerciseSearch")
                    if !query.search.isEmpty {
                        Button { query.search = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                            .buttonStyle(.plain).foregroundStyle(FitTheme.textSecondary).accessibilityLabel("Clear search")
                    }
                }
                .padding(.leading, 14).padding(.trailing, query.search.isEmpty ? 14 : 0).frame(minHeight: 50)
                .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(searchFocused ? FitTheme.dashboardAccent : FitTheme.subtleBorder, lineWidth: 1) }
                if searchFocused {
                    Button("Done") { searchFocused = false }.font(FitTheme.button(14)).frame(minWidth: 44, minHeight: 44)
                }
            }
            if !searchFocused {
                if typeSize.isAccessibilitySize {
                    Picker("Show exercises", selection: $query.scope) {
                        ForEach(ExerciseLibraryScope.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.menu).font(FitTheme.medium(14)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    HStack(spacing: 4) {
                        ForEach(ExerciseLibraryScope.allCases) { scope in
                            Button { query.scope = scope } label: {
                                Text(scope.rawValue).font(FitTheme.medium(12)).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(query.scope == scope ? FitTheme.textPrimary : FitTheme.textSecondary)
                                    .background(query.scope == scope ? FitTheme.elevated : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(RoutineEditorPressStyle()).accessibilityAddTraits(query.scope == scope ? .isSelected : [])
                        }
                    }.padding(4).background(FitTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                filterControlLayout {
                    Button { searchFocused = false; showFilters = true } label: {
                        Label(query.filters.count == 0 ? "Filters" : "Filters · \(query.filters.count)", systemImage: "line.3.horizontal.decrease")
                            .font(FitTheme.medium(13)).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 44)
                            .dashboardGlass(in: Capsule(), highlighted: query.filters.count > 0, interactive: true)
                    }.buttonStyle(RoutineEditorPressStyle()).accessibilityIdentifier("exerciseFilters")
                    Menu {
                        Picker("Sort exercises", selection: $query.sort) { ForEach(ExerciseSortOrder.allCases) { Text($0.rawValue).tag($0) } }
                    } label: {
                        Label("Sort · \(query.sort.shortTitle)", systemImage: "arrow.up.arrow.down")
                            .font(FitTheme.medium(13)).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 44)
                            .dashboardGlass(in: Capsule(), interactive: true)
                    }.accessibilityLabel("Sort exercises").accessibilityValue(query.sort.rawValue)
                }
            }
        }
        .frame(maxWidth: 560).padding(.horizontal, FitTheme.pageInset).padding(.vertical, 10)
        .frame(maxWidth: .infinity).background(FitTheme.dashboardBackground)
    }

    private var filterControlLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    }

    private var activeFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(query.filters.muscles) { muscle in
                    ExerciseChoiceChip(title: muscle.title, symbol: "xmark", selected: true) { query.filters.muscles.removeAll { $0 == muscle } }
                        .accessibilityLabel("Remove \(muscle.title) filter")
                }
                if let equipment = query.filters.equipment {
                    ExerciseChoiceChip(title: equipment.rawValue, symbol: "xmark", selected: true) { query.filters.equipment = nil }
                        .accessibilityLabel("Remove equipment filter")
                }
                if let category = query.filters.category {
                    ExerciseChoiceChip(title: category.rawValue, symbol: "xmark", selected: true) { query.filters.category = nil }
                        .accessibilityLabel("Remove type filter")
                }
                Button("Clear filters") { query.filters = ExerciseBrowseFilters() }.font(FitTheme.medium(12)).frame(minHeight: 44)
            }
        }
    }

    private func exerciseCard(_ exercise: ExerciseDefinition) -> some View {
        let index = selection.ids.firstIndex(of: exercise.id)
        return HStack(spacing: 0) {
            Group {
                if mode == .browse {
                    NavigationLink { ExerciseDetail(store: store, exerciseID: exercise.id) } label: { cardLabel(exercise, index: nil) }
                } else {
                    Button {
                        if mode == .single { searchFocused = false; onSelect?([exercise]) }
                        else { selection.toggle(exercise.id) }
                    } label: { cardLabel(exercise, index: index) }
                    .accessibilityIdentifier("pickExercise-\(exercise.id)")
                    .accessibilityValue(index.map { "Selected, position \($0 + 1)" } ?? "Not selected")
                    .accessibilityAddTraits(index == nil ? [] : .isSelected)
                }
            }.buttonStyle(RoutineEditorPressStyle()).accessibilityLabel(exercise.name)
            Menu {
                Button("View details", systemImage: "info.circle") { searchFocused = false; inspecting = exercise }
                Button(exercise.isFavorite ? "Remove favorite" : "Add to favorites", systemImage: exercise.isFavorite ? "star.slash" : "star") {
                    var updated = exercise; updated.isFavorite.toggle(); store.saveExercise(updated)
                }
            } label: { Image(systemName: "ellipsis").font(.system(size: 16)).foregroundStyle(FitTheme.textSecondary).frame(width: 44, height: 52) }
                .accessibilityLabel("Options for \(exercise.name)")
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 8)
        .background(index == nil ? FitTheme.surface : FitTheme.dashboardAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(index == nil ? FitTheme.textPrimary.opacity(0.045) : FitTheme.dashboardAccent.opacity(0.65), lineWidth: 1) }
    }

    private func cardLabel(_ exercise: ExerciseDefinition, index: Int?) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                ExerciseLibraryRow(exercise: exercise, artworkSize: typeSize.isAccessibilitySize ? 40 : 64)
                if let previous = previousPerformance?(exercise) {
                    Text("Last recorded · " + previous).font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
                }
            }
            if mode == .multiple {
                ZStack {
                    Circle().fill(index == nil ? .clear : FitTheme.dashboardAccent)
                    Circle().strokeBorder(index == nil ? FitTheme.textSecondary.opacity(0.4) : .clear, lineWidth: 1.5)
                    if let index { Text("\(index + 1)").font(FitTheme.strong(12)).foregroundStyle(FitTheme.textPrimary).lineLimit(1).minimumScaleFactor(0.5) }
                }.frame(width: 25, height: 25).accessibilityHidden(true)
            } else {
                Image(systemName: mode == .browse ? "chevron.right" : "plus.circle")
                    .font(.system(size: mode == .browse ? 12 : 22)).foregroundStyle(FitTheme.dashboardAccent).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
    }

    private var selectionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !searchFocused {
                HStack {
                    Button { reviewSelection.toggle() } label: {
                        Label("\(chosen.count) selected", systemImage: reviewSelection ? "chevron.down" : "list.bullet")
                            .font(FitTheme.medium(13)).frame(minHeight: 44)
                    }.disabled(chosen.isEmpty)
                    Spacer()
                    if !chosen.isEmpty { Button("Clear") { selection.clear(); reviewSelection = false }.font(FitTheme.medium(12)).frame(minHeight: 44) }
                }
                if reviewSelection && !chosen.isEmpty { selectionTray }
            }
            Button { searchFocused = false; onSelect?(chosen) } label: {
                HStack {
                    Text(chosen.isEmpty ? "Select exercises to add" : "Add \(chosen.count) \(chosen.count == 1 ? "exercise" : "exercises")")
                    Spacer(minLength: 4)
                    Image(systemName: "plus")
                }
                .font(FitTheme.button(15)).padding(.horizontal, 16).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(FitTheme.dashboardAccent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(RoutineEditorPressStyle()).disabled(chosen.isEmpty).opacity(chosen.isEmpty ? 0.45 : 1)
            .accessibilityIdentifier("confirmRoutineExercises")
        }
        .frame(maxWidth: 560).padding(.horizontal, FitTheme.pageInset).padding(.vertical, 10)
        .frame(maxWidth: .infinity).background(.bar)
    }

    private var selectionTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(chosen.enumerated()), id: \.element.id) { index, exercise in
                    HStack(spacing: 8) {
                        Text("\(index + 1). \(exercise.name)").font(FitTheme.medium(12))
                        Button { selection.remove(exercise.id) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 44, height: 44) }
                            .accessibilityLabel("Remove \(exercise.name) from selection")
                    }.padding(.leading, 12).background(FitTheme.surface, in: Capsule())
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.scope == .favorites ? "star" : "magnifyingglass").font(.system(size: 32, weight: .light))
                .foregroundStyle(FitTheme.dashboardAccent).frame(width: 80, height: 80).dashboardGlass(in: Circle())
            Text(query.scope == .favorites ? "No matching favorites" : "No matching exercises").font(FitTheme.section(19))
            Text("Try another search or clear the filters. You can also create your own exercise.")
                .font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary).multilineTextAlignment(.center)
            Button("Clear search & filters") { query.search = ""; query.filters = ExerciseBrowseFilters(); query.scope = .all }.font(FitTheme.button(14)).frame(minHeight: 44)
            Button("Create an exercise") { createExercise() }.font(FitTheme.medium(13)).frame(minHeight: 44)
        }.frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    private func createExercise() {
        searchFocused = false
        custom = ExerciseDefinition(name: query.search.trimmingCharacters(in: .whitespacesAndNewlines), muscles: query.filters.muscles, isCustom: true)
    }
}

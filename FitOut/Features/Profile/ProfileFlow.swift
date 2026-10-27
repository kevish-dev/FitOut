import SwiftUI
import PhotosUI

// The reference screens share presentation with the original onboarding, while
// ProfileStore remains the sole owner of the persisted, canonical profile.
struct ProfileFlow: View {
    @Environment(\.fitHaptics) private var haptics
    @Bindable var store: ProfileStore
    @State private var showNameError = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var referenceProfile: Binding<FitnessProfile> {
        Binding(get: {
            var value = FitnessProfile()
            let draft = store.draft
            value.name = draft.name; value.age = draft.age
            value.gender = draft.gender ?? .male
            value.emoji = draft.emoji; value.photoData = draft.avatarData
            value.usesPhoto = draft.avatarData != nil
            value.currentWeightKG = draft.currentWeightKG
            value.targetWeightKG = draft.targetWeightKG ?? draft.currentWeightKG
            value.unit = draft.weightUnit
            return value
        }, set: { value in
            var draft = store.draft
            draft.name = value.name; draft.age = value.age
            // An untouched optional gender must remain unspecified.
            if value.gender != (draft.gender ?? .male) { draft.gender = value.gender }
            draft.emoji = value.emoji
            draft.avatarData = value.usesPhoto ? value.photoData : nil
            draft.currentWeightKG = value.currentWeightKG
            if draft.targetWeightKG != nil { draft.targetWeightKG = value.targetWeightKG }
            draft.weightUnit = value.unit
            store.draft = draft
        })
    }

    var body: some View {
        ZStack {
            FitTheme.background.ignoresSafeArea()
            if store.draft.step == 0 {
                WelcomeScreen { store.draft.step = 1 }
            } else {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / 390, 1.15)
                    VStack(spacing: 0) {
                        StepProgress(step: min(5, store.draft.step), totalSteps: 5)
                            .padding(.top, 24).padding(.bottom, 36)
                        ScrollView {
                            VStack(spacing: 16) {
                                switch store.draft.step {
                                case 1:
                                    ProfileScreen(profile: referenceProfile, showNameError: showNameError, scale: scale)
                                case 2:
                                    GenderAgeScreen(profile: referenceProfile, scale: scale,
                                        selectedGender: store.draft.gender,
                                        onGenderSelected: { store.draft.gender = $0 })
                                    Button("Prefer not to say") { store.draft.gender = nil }
                                        .foregroundStyle(store.draft.gender == nil ? FitTheme.orange : .secondary)
                                        .accessibilityAddTraits(store.draft.gender == nil ? .isSelected : [])
                                case 3:
                                    HeightScreen(heightCM: $store.draft.heightCM, unit: $store.draft.heightUnit, scale: scale)
                                case 4:
                                    WeightScreen(profile: referenceProfile, scale: scale,
                                        targetEnabled: store.draft.targetWeightKG != nil,
                                        onEnableTarget: { store.draft.targetWeightKG = store.draft.currentWeightKG })
                                    measurementFields
                                default:
                                    goalSelection(scale: scale)
                                }
                            }
                            .frame(maxWidth: 460).frame(maxWidth: .infinity)
                            .padding(.horizontal, FitTheme.pageInset).padding(.bottom, FitTheme.sectionSpacing)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .id(store.draft.step)
                        HStack(spacing: 14) {
                            BackButton {
                                showNameError = false
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                                    store.draft.step = max(0, store.draft.step - 1)
                                }
                            }
                            if store.draft.step >= 5 {
                                SlideToFinish(enabled: store.draft.validationMessage == nil) { _ = store.complete() }
                            } else {
                                Spacer()
                                NextButton { advance() }
                            }
                        }
                        .padding(.horizontal, FitTheme.pageInset).padding(.top, 12).padding(.bottom, 22)
                    }
                }
            }
        }
        .foregroundStyle(FitTheme.textPrimary)

        .tint(FitTheme.orange)
        .alert("Profile could not be saved", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Retry save") { store.saveDraft() }
            Button("OK", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
    }

    private func advance() {
        if store.draft.step == 1 && (store.draft.trimmedName.isEmpty || store.draft.trimmedName.count > 40) {
            showNameError = true
            haptics?.play(.warning)
            return
        }
        if store.draft.step == 3 && (!store.draft.heightCM.isFinite || !(80...250).contains(store.draft.heightCM)) {
            store.error = "Height must be between 80 and 250 cm."
            return
        }
        showNameError = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            store.draft.step = min(5, store.draft.step + 1)
        }
    }

    private var measurementFields: some View {
        VStack(spacing: 16) {
            Toggle("Set a target weight (optional)", isOn: Binding(
                get: { store.draft.targetWeightKG != nil },
                set: { store.draft.targetWeightKG = $0 ? store.draft.currentWeightKG : nil }))
        }
        .font(FitTheme.body(18)).padding(FitTheme.cardInset).fitSurface(radius: 14)
    }

    private func goalSelection(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "Your Fitness", accent: "Goals", size: 31 * scale)
                .padding(.bottom, 46 * scale)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16 * scale) {
                ForEach(PrimaryGoal.allCases) { goal in
                    let selected = store.draft.primaryGoal == goal
                    Button { store.draft.primaryGoal = goal; haptics?.play(.selection) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: goal.symbol).font(.system(size: 21 * scale, weight: .semibold))
                            Text(goal.rawValue).font(FitTheme.button(13 * scale))
                                .lineLimit(2).minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(selected ? FitTheme.orange : FitTheme.textPrimary)
                        .padding(.horizontal, 12).frame(maxWidth: .infinity)
                        .frame(height: 62 * scale).fitSurface(selected: selected, radius: 15)
                    }
                    .buttonStyle(.fitPlain).accessibilityLabel(goal.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text("Choose one primary goal. You can change it in Settings.")
                .font(FitTheme.body(16)).foregroundStyle(.secondary).padding(.top, 20)
        }
    }
}

private extension PrimaryGoal {
    var symbol: String {
        switch self {
        case .muscle: "dumbbell.fill"
        case .fatLoss: "flame"
        case .recomposition: "figure.stand"
        case .strength: "chart.bar.fill"
        case .endurance: "figure.run"
        case .fitness: "heart.fill"
        }
    }
}

private struct HeightScreen: View {
    @Environment(\.fitHaptics) private var haptics
    @Binding var heightCM: Double
    @Binding var unit: HeightUnit
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "What’s your", accent: "height?", size: 30 * scale)
            Text("Used for better progress tracking.")
                .font(FitTheme.body(18)).foregroundStyle(FitTheme.textPrimary.opacity(0.6))
                .padding(.top, 12).padding(.bottom, 30 * scale)
            HeightWheel(heightCM: $heightCM, unit: unit, scale: scale)
                .id(unit)
                .frame(width: 230 * scale, height: 300 * scale)
                .padding(.bottom, 30 * scale)
            HStack(spacing: 0) {
                unitButton("cm", value: .cm)
                unitButton("in", value: .feet)
            }
            .fitSurface(radius: 12)
            .frame(width: 156 * scale)
        }
    }

    private func unitButton(_ title: String, value: HeightUnit) -> some View {
        Button {
            unit = value
            haptics?.play(.selection)
        } label: {
            Text(title).font(FitTheme.button(17))
                .foregroundStyle(unit == value ? FitTheme.orange : FitTheme.textPrimary.opacity(0.8))
                .frame(maxWidth: .infinity).frame(height: 42)
                .fitSurface(selected: unit == value, radius: 12)
        }
        .buttonStyle(.fitPlain)
        .accessibilityLabel(value == .cm ? "Centimeters" : "Inches")
        .accessibilityAddTraits(unit == value ? .isSelected : [])
    }
}

private struct HeightWheel: View {
    @Environment(\.fitHaptics) private var haptics
    @Binding var heightCM: Double
    let unit: HeightUnit
    let scale: CGFloat
    @State private var selectedTick: Int?
    @State private var isScrolling = false
    private var imperial: Bool { unit != .cm }
    private var ticks: ClosedRange<Int> { imperial ? 315...984 : 80...250 }
    private var rowHeight: CGFloat { 52 * scale }
    private var currentTick: Int {
        let value = imperial ? heightCM / 2.54 * 10 : heightCM
        return min(ticks.upperBound, max(ticks.lowerBound, Int(value.rounded())))
    }

    private func commit() {
        guard let selectedTick else { return }
        let value = imperial ? Double(selectedTick) / 10 * 2.54 : Double(selectedTick)
        let bounded = min(250, max(80, value))
        if abs(heightCM - bounded) > 0.00001 { heightCM = bounded; haptics?.play(.selection) }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(FitTheme.orange.opacity(0.07))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(FitTheme.orange, lineWidth: 1.4) }
                    .frame(height: rowHeight + 12)
                    .allowsHitTesting(false)
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(ticks, id: \.self) { tick in
                            let selected = tick == selectedTick
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text(imperial ? (Double(tick) / 10).formatted(.number.precision(.fractionLength(0...1))) : String(tick))
                                    .font(selected ? FitTheme.display(32 * scale) : FitTheme.body(25 * scale))
                                    .foregroundStyle(selected ? FitTheme.orange : FitTheme.textPrimary.opacity(0.55))
                                if selected {
                                    Text(imperial ? "in" : "cm")
                                        .font(FitTheme.body(17)).foregroundStyle(FitTheme.textPrimary.opacity(0.6))
                                }
                            }
                            .frame(maxWidth: .infinity).frame(height: rowHeight)
                            .id(tick)
                        }
                    }
                    .scrollTargetLayout()
                }
                .safeAreaPadding(.vertical, max(0, (geometry.size.height - rowHeight) / 2))
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedTick, anchor: .center)
                .mask { LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom) }
                .onAppear { selectedTick = currentTick }
                .onChange(of: heightCM) { _, _ in if !isScrolling { selectedTick = currentTick } }
                .onScrollPhaseChange { _, phase in
                    isScrolling = phase != .idle
                    if phase == .idle { commit() }
                }
                .onDisappear { if isScrolling { commit() } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your height")
        .accessibilityValue(imperial ? "\((Double(selectedTick ?? currentTick) / 10).formatted()) inches" : "\(selectedTick ?? currentTick) centimeters")
        .accessibilityAdjustableAction { direction in
            let tick = selectedTick ?? currentTick
            switch direction {
            case .increment: selectedTick = min(ticks.upperBound, tick + 1)
            case .decrement: selectedTick = max(ticks.lowerBound, tick - 1)
            @unknown default: return
            }
            commit()
        }
        .accessibilityIdentifier("heightPicker")
    }
}

struct ProfileFields: View {
    @Binding var profile: ProfileData
    @State private var picker: PhotosPickerItem?
    @State private var showPicker = false
    @State private var photoError: String?
    var body: some View {
        Section("Personal information") {
            TextField("Name", text: $profile.name).textContentType(.givenName).accessibilityIdentifier("profileName")
            Stepper("Age: \(profile.age)", value: $profile.age, in: 13...100)
            Picker("Gender (optional)", selection: $profile.gender) {
                Text("Not specified").tag(Gender?.none)
                ForEach(Gender.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            Text("Gender is optional profile information. It is not used to infer health conditions.").font(FitTheme.body(12)).foregroundStyle(.secondary)
        }
        Section("Units and measurements") {
            Picker("Weight units", selection: $profile.weightUnit) { ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Height units", selection: $profile.heightUnit) { Text("cm").tag(HeightUnit.cm); Text("ft/in").tag(HeightUnit.feet) }
            if profile.heightUnit == .cm { numeric("Height (cm)", value: $profile.heightCM) }
            else {
                let parts = ProfileData.feetAndInches(profile.heightCM)
                Stepper("Feet: \(parts.feet)", value: Binding(get: { parts.feet }, set: { profile.heightCM = ProfileData.centimeters(feet: $0, inches: parts.inches) }), in: 2...8)
                numeric("Inches", value: Binding(get: { ProfileData.feetAndInches(profile.heightCM).inches }, set: { profile.heightCM = ProfileData.centimeters(feet: parts.feet, inches: min(11.99, max(0, $0))) }))
            }
            numeric("Current weight (\(profile.weightUnit.rawValue))", value: Binding(get: { profile.weightUnit.display(profile.currentWeightKG) }, set: { profile.currentWeightKG = profile.weightUnit.kilograms($0) }))
            Toggle("Set a target weight (optional)", isOn: Binding(get: { profile.targetWeightKG != nil }, set: { profile.targetWeightKG = $0 ? profile.currentWeightKG : nil }))
            if profile.targetWeightKG != nil {
                numeric("Target weight (\(profile.weightUnit.rawValue))", value: Binding(get: { profile.weightUnit.display(profile.targetWeightKG ?? profile.currentWeightKG) }, set: { profile.targetWeightKG = profile.weightUnit.kilograms($0) }))
                Text("A personal reference for tracking your progress; it is not a medical recommendation.").font(FitTheme.body(12)).foregroundStyle(.secondary)
            }
        }
        Section("Avatar (optional)") {
            TextField("Emoji", text: $profile.emoji)
            Button("Choose photo") { showPicker = true }
            if profile.avatarData != nil { Button("Remove photo", role: .destructive) { profile.avatarData = nil } }
            if let photoError { Text(photoError).foregroundStyle(.red) }
        }
        .photosPicker(isPresented: $showPicker, selection: $picker, matching: .images)
        .onChange(of: picker) { _, selected in
            Task {
                do {
                    guard let data = try await selected?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    let size = CGSize(width: 360, height: 360)
                    let result = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                    profile.avatarData = result.jpegData(compressionQuality: 0.85); photoError = nil
                } catch { photoError = "The photo could not be read. Try another image." }
            }
        }
    }
    private func numeric(_ title: String, value: Binding<Double>) -> some View {
        HStack { Text(title); Spacer(); TextField(title, value: value, format: .number.precision(.fractionLength(0...2))).multilineTextAlignment(.trailing).keyboardType(.decimalPad).frame(maxWidth: 110) }
    }
}

struct ProfileEditor: View {
    let store: ProfileStore
    let presentation: AppPresentationPreferences
    @State private var draft: ProfileData
    @Environment(\.dismiss) private var dismiss
    init(store: ProfileStore, presentation: AppPresentationPreferences) { self.store = store; self.presentation = presentation; _draft = State(initialValue: store.draft) }
    var body: some View {
        Form {
            ProfilePresentationSection(preferences: presentation)
            Section("Primary goal") { Picker("Goal", selection: $draft.primaryGoal) { ForEach(PrimaryGoal.allCases) { Text($0.rawValue).tag(Optional($0)) } } }
            ProfileFields(profile: $draft)
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Edit profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if store.complete(draft) { dismiss() } }
                    .padding(.trailing, presentation.navigationStyle == .topRight ? 68 : 0)
            } }
    }
}

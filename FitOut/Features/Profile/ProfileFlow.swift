import SwiftUI
import PhotosUI

struct ProfileFlow: View {
    @Bindable var store: ProfileStore
    var body: some View {
        NavigationStack {
            Group {
                if store.draft.step == 0 { WelcomeScreen { store.draft.step = 1 } }
                else if store.draft.step == 1 {
                    List {
                        Section { Text("Choose one primary goal. You can change it in Settings.") }
                        ForEach(PrimaryGoal.allCases) { goal in
                            Button { store.draft.primaryGoal = goal } label: {
                                HStack { Text(goal.rawValue); Spacer(); if store.draft.primaryGoal == goal { Image(systemName: "checkmark.circle.fill") } }
                            }.accessibilityAddTraits(store.draft.primaryGoal == goal ? .isSelected : [])
                        }
                        Button("Continue") { store.draft.step = 2 }
                            .disabled(store.draft.primaryGoal == nil).accessibilityIdentifier("profileContinue")
                        Button("Back") { store.draft.step = 0 }
                    }.navigationTitle("Your fitness goal")
                } else {
                    Form {
                        ProfileFields(profile: $store.draft)
                        Button("Create my journey") { _ = store.complete() }.accessibilityIdentifier("completeProfile")
                        Button("Back") { store.draft.step = 1 }
                    }.navigationTitle("Your profile")
                }
            }
            .alert("Profile could not be saved", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Retry save") { store.saveDraft() }
                Button("OK", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
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
            Text("Gender is optional profile information. It is not used to infer health conditions.").font(.caption).foregroundStyle(.secondary)
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
                Text("A personal reference for tracking your progress; it is not a medical recommendation.").font(.caption).foregroundStyle(.secondary)
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
    @State private var draft: ProfileData
    @Environment(\.dismiss) private var dismiss
    init(store: ProfileStore) { self.store = store; _draft = State(initialValue: store.draft) }
    var body: some View {
        Form {
            Section("Primary goal") { Picker("Goal", selection: $draft.primaryGoal) { ForEach(PrimaryGoal.allCases) { Text($0.rawValue).tag(Optional($0)) } } }
            ProfileFields(profile: $draft)
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Edit profile")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.complete(draft) { dismiss() } } } }
    }
}

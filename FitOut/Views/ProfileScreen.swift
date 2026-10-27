import PhotosUI
import SwiftUI

struct ProfileScreen: View {
    @Environment(\.fitHaptics) private var haptics
    @Binding var profile: FitnessProfile
    let showNameError: Bool
    var scale: CGFloat = 1
    @State private var photo: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var photoError: String?
    @State private var isLoadingPhoto = false
    @State private var selectedAvatar = false
    @State private var emojiPage = 0
    @FocusState private var isNameFocused: Bool

    private let emojiPages = [
        ["💪", "🔥", "🦁", "🐺", "🐼", "😎", "🏃", "🙂", "🚀", "💎", "👑", "⚡️", "🏔️", "🎯", "🎮"],
        ["🐯", "🦊", "🐻", "🐨", "🐸", "🦋", "🦅", "🏋️", "🧘", "🏊", "🚴", "🥊", "🏆", "🥇", "⭐️"],
        ["🌊", "☀️", "🌙", "🌈", "🌻", "🌴", "🍀", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"],
        ["🥷", "🦸", "🧑‍🚀", "🤖", "👽", "👻", "🦄", "🐉", "🐬", "🦈", "🐙", "🦖", "🦕", "🐝", "🐢"]
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeading(first: "Let’s set up", accent: "your profile", size: 28 * scale)
                .padding(.bottom, 34 * scale)
            AvatarView(profile: profile, size: 108 * scale, placeholder: !selectedAvatar && profile.name.isEmpty && profile.emoji == "💪")
                .overlay { if isLoadingPhoto { ProgressView().tint(FitTheme.orange) } }
                .padding(.bottom, 20 * scale)
            VStack(alignment: .leading, spacing: 8) {
                Text("Your name").font(FitTheme.section(16))
                TextField("Enter your name", text: $profile.name)
                    .font(FitTheme.medium(16))
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }
                    .padding(.horizontal, FitTheme.cardInset).frame(height: 44)
                    .fitSurface(radius: 11)
                    .accessibilityIdentifier("nameField")
                    .onChange(of: profile.name) { _, value in
                        if value.count > 40 { profile.name = String(value.prefix(40)) }
                    }
                if showNameError && !profile.isNameValid {
                    Text("Enter your name to continue.")
                        .font(FitTheme.medium(12)).foregroundStyle(FitTheme.orange)
                        .accessibilityIdentifier("nameError")
                }
            }
            .padding(.bottom, 24 * scale)
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose your avatar").font(FitTheme.section(16))
                HStack(spacing: 0) {
                    Button {
                        photo = nil
                        profile.usesPhoto = false
                        isNameFocused = false
                    } label: {
                        Label("Emoji", systemImage: "face.smiling.fill")
                            .font(FitTheme.medium(15))
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .foregroundStyle(!profile.usesPhoto ? FitTheme.orange : FitTheme.textPrimary)
                            .fitSurface(selected: !profile.usesPhoto, radius: 13)
                    }.buttonStyle(.fitPlain)
                    Button {
                        isNameFocused = false
                        photoError = nil
                        photo = nil
                        showPhotoPicker = true
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                            .font(FitTheme.medium(15))
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .foregroundStyle(profile.usesPhoto ? FitTheme.orange : FitTheme.textPrimary)
                            .fitSurface(selected: profile.usesPhoto, radius: 13)
                    }
                    .buttonStyle(.fitPlain)
                    .accessibilityIdentifier("uploadAvatarButton")
                }.fitSurface(radius: 13)
            }
            .padding(.bottom, 18 * scale)
            TabView(selection: $emojiPage) {
                ForEach(emojiPages.indices, id: \.self) { page in
                    VStack(spacing: 8) {
                        emojiRow(Array(emojiPages[page].prefix(7)))
                        emojiRow(Array(emojiPages[page].suffix(8)))
                    }
                    .tag(page)
                    .padding(.horizontal, 1)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 96 * scale)
            HStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { page in
                    Button { emojiPage = page } label: {
                        Capsule().fill(emojiPage == page ? FitTheme.orange : FitTheme.textPrimary.opacity(0.13))
                            .frame(width: 24, height: 4)
                            .frame(height: 32)
                    }
                    .buttonStyle(.fitPlain)
                    .accessibilityLabel("Avatar page \(page + 1)")
                    .accessibilityAddTraits(emojiPage == page ? .isSelected : [])
                }
            }.padding(.top, 4)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photo, matching: .images)
        .task(id: photo) { await loadPhoto() }
        .alert("Photo unavailable", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) { photoError = nil }
        } message: { Text(photoError ?? "") }
    }

    private func emojiRow(_ emojis: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(emojis, id: \.self) { emoji in
                let selected = profile.emoji == emoji && !profile.usesPhoto
                Button {
                    photo = nil
                    profile.emoji = emoji
                    profile.usesPhoto = false
                    selectedAvatar = true
                    isNameFocused = false
                    haptics?.play(.selection)
                } label: {
                    Text(emoji).font(.system(size: 25 * scale))
                        .frame(width: 39 * scale, height: 39 * scale)
                        .fitSurface(selected: selected, radius: 25)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.fitPlain)
                .accessibilityLabel("\(emoji) avatar")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @MainActor private func loadPhoto() async {
        guard let item = photo else { return }
        isNameFocused = false
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let original = UIImage(data: data) else {
                photoError = "Please choose a supported photo from your library."
                return
            }
            try Task.checkCancellation()
            // Crop to a small square before persisting so large library images never fill preferences.
            let size = CGSize(width: 360, height: 360)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                let ratio = max(size.width / original.size.width, size.height / original.size.height)
                let scaled = CGSize(width: original.size.width * ratio, height: original.size.height * ratio)
                original.draw(in: CGRect(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2, width: scaled.width, height: scaled.height))
            }
            guard let encoded = resized.jpegData(compressionQuality: 0.85) else {
                photoError = "This photo could not be prepared. Please try another image."
                return
            }
            // The binding derives usesPhoto from saved avatar data. Commit both
            // together so it cannot discard the image between field updates.
            var updated = profile
            updated.photoData = encoded
            updated.usesPhoto = true
            profile = updated
            selectedAvatar = true
        } catch is CancellationError {
            return
        } catch {
            photoError = "This photo could not be loaded. Please try another image."
        }
    }
}

import SwiftUI

struct OnboardingView: View {
    @Environment(\.fitHaptics) private var haptics
    @Bindable var store: OnboardingStore
    @State private var showNameError = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func advance() {
        if store.step == 1 && !store.profile.isNameValid {
            showNameError = true
            haptics?.play(.warning)
            return
        }
        showNameError = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { store.step = min(4, store.step + 1) }
    }

    var body: some View {
        ZStack {
            FitTheme.background.ignoresSafeArea()
            if store.profile.completedAt != nil {
                CompletionScreen(store: store)
            } else if store.step == 0 {
                WelcomeScreen { advance() }
            } else {
                GeometryReader { geometry in
                    let scale = min(geometry.size.width / 390, 1.15)
                    VStack(spacing: 0) {
                        StepProgress(step: store.step)
                            .padding(.top, 24).padding(.bottom, 36)
                        ScrollView {
                            Group {
                                switch store.step {
                                case 1: ProfileScreen(profile: $store.profile, showNameError: showNameError, scale: scale)
                                case 2: GenderAgeScreen(profile: $store.profile, scale: scale)
                                case 3: WeightScreen(profile: $store.profile, scale: scale)
                                default: GoalsScreen(profile: $store.profile, scale: scale)
                                }
                            }
                            .frame(maxWidth: 460)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, FitTheme.pageInset)
                            .padding(.bottom, 16)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)
                        .id(store.step)
                        HStack(spacing: 14) {
                            BackButton {
                                showNameError = false
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { store.step = max(0, store.step - 1) }
                            }
                            if store.step == 4 {
                                SlideToFinish(enabled: store.profile.canComplete) { _ = store.complete() }
                            } else {
                                Spacer()
                                NextButton { advance() }
                            }
                        }
                        .padding(.horizontal, FitTheme.pageInset)
                        .padding(.top, 12)
                        .padding(.bottom, 22)
                    }
                }
            }
        }
        .foregroundStyle(FitTheme.textPrimary)
        .alert("Unable to save", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button("OK", role: .cancel) { store.storageError = nil }
        } message: { Text(store.storageError ?? "") }
    }
}

struct WelcomeScreen: View {
    @Environment(\.fitHaptics) private var haptics
    @Environment(\.colorScheme) private var scheme
    let onStart: () -> Void
    @State private var slideOffset: CGFloat = 0
    @State private var started = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func start() {
        guard !started else { return }
        started = true
        haptics?.play(.navigation)
        onStart()
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                GeometryReader { background in
                    Image("FitnessHero").resizable().scaledToFill()
                        .frame(width: background.size.width, height: background.size.height)
                        .clipped()
                        .overlay { if scheme == .light { FitTheme.background.opacity(0.65) } }
                }.ignoresSafeArea()
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: FitTheme.background.opacity(0.12), location: 0.7), .init(color: FitTheme.background.opacity(0.7), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("STRONGER\nHEALTHIER\nHAPPIER\nYOU")
                        .font(FitTheme.medium(11)).tracking(3.7).lineSpacing(4)
                        .foregroundStyle(FitTheme.textPrimary.opacity(0.8))
                    HStack(spacing: 0) {
                        Rectangle().fill(FitTheme.orange).frame(width: 26)
                        Rectangle().fill(FitTheme.textPrimary.opacity(0.2)).frame(width: 40)
                    }.frame(height: 2.5)
                }
                .padding(.leading, FitTheme.pageInset)
                .padding(.top, geometry.size.height * 0.075)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR")
                        Text("FITNESS").foregroundStyle(FitTheme.orange)
                        Text("JOURNEY")
                        Text("STARTS HERE")
                    }
                    .font(FitTheme.hero(width * 0.077))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text("Track workouts, stay consistent,\nand build a healthier, stronger you.")
                        .font(FitTheme.body(width * 0.037))
                        .foregroundStyle(FitTheme.textPrimary.opacity(0.7))
                        .lineSpacing(3)
                }
                .padding(.horizontal, FitTheme.pageInset)
                .offset(y: geometry.size.height * 0.36)
                VStack {
                    Spacer()
                    GeometryReader { track in
                        let travel = max(0, track.size.width - 64)
                        ZStack(alignment: .leading) {
                            Text("Get Started")
                                .font(FitTheme.label(17)).tracking(1)
                                .foregroundStyle(FitTheme.orange)
                                .frame(maxWidth: .infinity)
                                .padding(.leading, 64)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 55)
                                .background(FitTheme.orange, in: RoundedRectangle(cornerRadius: 9))
                                .contentShape(Rectangle())
                                .offset(x: slideOffset)
                                .gesture(DragGesture(minimumDistance: 3)
                                    .onChanged { value in
                                        guard !started else { return }
                                        slideOffset = min(travel, max(0, value.translation.width))
                                    }
                                    .onEnded { _ in
                                        if travel > 0 && slideOffset >= travel * 0.85 {
                                            slideOffset = travel
                                            start()
                                        } else {
                                            withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                                                slideOffset = 0
                                            }
                                        }
                                    })
                        }
                        .frame(height: 55)
                        .background(FitTheme.surface.opacity(0.85))
                        .fitSurface(radius: 9)
                    }
                    .frame(height: 55)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Get Started")
                    .accessibilityHint("Slide the arrow to the right to continue, or double tap.")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { start() }
                    .accessibilityIdentifier("getStartedButton")
                    .padding(.horizontal, FitTheme.pageInset)
                    .padding(.bottom, 25)
                }
            }
        }
    }
}


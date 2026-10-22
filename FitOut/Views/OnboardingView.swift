import SwiftUI

struct OnboardingView: View {
    @Bindable var store: OnboardingStore
    @State private var showNameError = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func advance() {
        if store.step == 1 && !store.profile.isNameValid {
            showNameError = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
                            .padding(.horizontal, 25)
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
                        .padding(.horizontal, 30)
                        .padding(.top, 12)
                        .padding(.bottom, 22)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .alert("Unable to save", isPresented: Binding(get: { store.storageError != nil }, set: { if !$0 { store.storageError = nil } })) {
            Button("OK", role: .cancel) { store.storageError = nil }
        } message: { Text(store.storageError ?? "") }
    }
}

struct WelcomeScreen: View {
    let onStart: () -> Void
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                GeometryReader { background in
                    Image("FitnessHero").resizable().scaledToFill()
                        .frame(width: background.size.width, height: background.size.height)
                        .clipped()
                }.ignoresSafeArea()
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.12), location: 0.7), .init(color: .black.opacity(0.7), location: 1)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("STRONGER\nHEALTHIER\nHAPPIER\nYOU")
                        .font(FitTheme.body(11)).tracking(3.7).lineSpacing(4)
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(spacing: 0) {
                        Rectangle().fill(FitTheme.orange).frame(width: 26)
                        Rectangle().fill(.white.opacity(0.2)).frame(width: 40)
                    }.frame(height: 2.5)
                }
                .padding(.leading, width * 0.087)
                .padding(.top, geometry.size.height * 0.075)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR")
                        Text("FITNESS").foregroundStyle(FitTheme.orange)
                        Text("JOURNEY")
                        Text("STARTS HERE")
                    }
                    .font(FitTheme.display(width * 0.077))
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text("Track workouts, stay consistent,\nand build a healthier, stronger you.")
                        .font(FitTheme.body(width * 0.037))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineSpacing(3)
                }
                .padding(.horizontal, width * 0.073)
                .offset(y: geometry.size.height * 0.36)
                VStack {
                    Spacer()
                    Button(action: onStart) {
                        HStack(spacing: 0) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.black)
                                .frame(width: 64, height: 55)
                                .background(FitTheme.orange, in: RoundedRectangle(cornerRadius: 9))
                            Text("Get Started")
                                .font(FitTheme.label(17)).tracking(1)
                                .foregroundStyle(FitTheme.orange)
                                .frame(maxWidth: .infinity)
                        }
                        .background(.black.opacity(0.5))
                        .fitSurface(radius: 9)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("getStartedButton")
                    .padding(.horizontal, width * 0.073)
                    .padding(.bottom, 25)
                }
            }
        }
    }
}


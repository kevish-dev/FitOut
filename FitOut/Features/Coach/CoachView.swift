import SwiftUI

struct CoachView: View {
    @Bindable var store: CoachStore
    let profile: ProfileData
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var followsLatest = true
    @State private var confirmingNewChat = false

    private var context: CoachContext { CoachContext(profile: profile, includeGoal: store.usesProfileGoal) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                        if !store.availability.isAvailable { unavailableNotice }
                        if store.messages.isEmpty && store.availability.isAvailable { welcome }
                        ForEach(store.messages) { message in
                            CoachMessageBubble(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("coachLatest")
                    }
                    .padding(.horizontal, FitTheme.pageInset)
                    .padding(.vertical, FitTheme.sectionSpacing)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 100
                } action: { _, nearBottom in followsLatest = nearBottom }
                .onChange(of: store.messages.count) { _, _ in
                    guard followsLatest else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("coachLatest", anchor: .bottom)
                    }
                }
                .onChange(of: store.messages.last?.text) { _, _ in
                    if followsLatest { proxy.scrollTo("coachLatest", anchor: .bottom) }
                }
            }
        }
        .background(FitTheme.dashboardBackground.ignoresSafeArea())
        .foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle("AI Coach")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { store.refreshAvailability() }
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshAvailability() }
            else { store.stop() }
        }
        .confirmationDialog("Start a new chat?", isPresented: $confirmingNewChat, titleVisibility: .visible) {
            Button("Clear chat", role: .destructive) { store.clear() }
        } message: {
            Text("This removes the messages in this chat.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI Coach")
                    .font(FitTheme.display(24))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("coachTitle")
                Text("Training, nutrition & recovery.")
                    .font(FitTheme.body(13))
                    .foregroundStyle(FitTheme.textSecondary)
            }
            .padding(.trailing, 68)
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(store.availability.isAvailable ? Color.green : FitTheme.textSecondary)
                        .frame(width: 5, height: 5)
                    Text(store.availability.isAvailable ? "ON-DEVICE" : "UNAVAILABLE")
                        .font(FitTheme.medium(10)).tracking(1.2)
                        .foregroundStyle(FitTheme.textSecondary)
                }
                Spacer()
                Button {
                    if !store.messages.isEmpty { confirmingNewChat = true }
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                        .font(FitTheme.medium(12))
                        .foregroundStyle(FitTheme.dashboardAccent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(store.messages.isEmpty)
                .opacity(store.messages.isEmpty ? 0.4 : 1)
                .accessibilityIdentifier("coachNewChat")
            }
            if store.availability.isAvailable, profile.primaryGoal != nil {
                Button { store.usesProfileGoal.toggle() } label: {
                    Label(store.usesProfileGoal ? "My fitness goal is included" : "Include my fitness goal",
                          systemImage: store.usesProfileGoal ? "checkmark.circle.fill" : "plus.circle")
                        .font(FitTheme.medium(12))
                        .foregroundStyle(store.usesProfileGoal ? FitTheme.dashboardAccent : FitTheme.textSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(store.isResponding)
                .accessibilityValue(store.usesProfileGoal ? "On" : "Off")
                .accessibilityIdentifier("coachIncludeGoal")
            }
        }
        .padding(.horizontal, FitTheme.pageInset)
        .padding(.top, 16)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(FitTheme.dashboardAccent)
                .frame(width: 64, height: 64)
                .dashboardGlass(in: RoundedRectangle(cornerRadius: 22), highlighted: true)
            Text("Your next step,\nmade clearer.")
                .font(FitTheme.display(23))
                .fixedSize(horizontal: false, vertical: true)
            Text("Talk through a workout, a meal, or a recovery day. What would you like to work on?")
                .font(FitTheme.body(14))
                .foregroundStyle(FitTheme.textSecondary)
            VStack(spacing: 10) {
                starter("Plan a 30-minute gym session", symbol: "dumbbell")
                starter("What can I eat before training?", symbol: "fork.knife")
                starter("How do I improve my squat?", symbol: "figure.strengthtraining.traditional")
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func starter(_ question: String, symbol: String) -> some View {
        Button {
            store.draft = question
            send()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(FitTheme.dashboardAccent)
                    .frame(width: 24)
                Text(question).font(FitTheme.medium(14)).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.system(size: 11))
                    .foregroundStyle(FitTheme.textSecondary)
            }
            .padding(FitTheme.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fitSurface(radius: 16)
        }
        .buttonStyle(.plain)
        .disabled(store.isResponding)
    }

    private var unavailableNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("On-device coach unavailable", systemImage: "sparkles")
                .font(FitTheme.section(17))
            Text(unavailableExplanation)
                .font(FitTheme.body(14))
                .foregroundStyle(FitTheme.textSecondary)
            Button("Check again") { store.refreshAvailability() }
                .font(FitTheme.button(13))
                .foregroundStyle(FitTheme.dashboardAccent)
                .frame(minHeight: 44)
        }
        .padding(FitTheme.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fitSurface(radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coachUnavailable")
    }

    private var unavailableExplanation: String {
        switch store.availability {
        case .available: "Ready to chat on this device."
        case .unavailable(.requiresOS(let version)): "AI Coach requires iOS \(version) or later and an iPhone that supports Apple Intelligence."
        case .unavailable(.deviceNotEligible): "This iPhone doesn't support the on-device model used by AI Coach."
        case .unavailable(.intelligenceDisabled): "Turn on Apple Intelligence in iPhone Settings, then return to FitOut."
        case .unavailable(.modelNotReady): "The on-device model is still preparing. Check again after it finishes downloading."
        case .unavailable(.systemUnavailable): "The on-device model isn't available right now. Check Apple Intelligence in Settings and try again."
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.errorMessage {
                Text(error).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
            }
            if store.canRetry {
                Button("Retry last reply") {
                    followsLatest = true
                    store.retry(context: context)
                }
                .font(FitTheme.button(12))
                .foregroundStyle(FitTheme.dashboardAccent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("coachRetry")
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(store.availability.isAvailable ? "Ask your fitness coach…" : "AI Coach unavailable", text: $store.draft, axis: .vertical)
                    .font(FitTheme.body(15))
                    .lineLimit(1...5)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .fitSurface(radius: 22)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .disabled(!store.availability.isAvailable)
                    .accessibilityLabel("Message your fitness coach")
                    .accessibilityIdentifier("coachMessageInput")
                Button {
                    if store.isResponding { store.stop() }
                    else { send() }
                } label: {
                    Image(systemName: store.isResponding ? "stop.fill" : "arrow.up")
                        .font(.system(size: store.isResponding ? 15 : 20, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 46, height: 46)
                        .background(FitTheme.dashboardAccent.opacity(store.isResponding || store.canSend ? 1 : 0.3), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!store.isResponding && !store.canSend)
                .accessibilityLabel(store.isResponding ? "Stop reply" : "Send message")
                .accessibilityIdentifier("coachSendOrStop")
            }
            if store.draft.count > 1_000 {
                Text("\(store.draft.count)/\(CoachConversation.maximumMessageLength) characters")
                    .font(FitTheme.medium(10))
                    .foregroundStyle(store.draft.count > CoachConversation.maximumMessageLength ? Color.orange : FitTheme.textSecondary)
            }
            Text("On-device · Uses your units and age group. Chat stays for this app session.")
                .font(FitTheme.body(10))
                .foregroundStyle(FitTheme.textSecondary)
        }
        .padding(.horizontal, FitTheme.pageInset)
        .padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(FitTheme.dashboardBackground)
    }

    private func send() {
        guard store.canSend else { return }
        followsLatest = true
        store.send(context: context)
    }
}

private struct CoachMessageBubble: View {
    let message: CoachMessage

    private var accessibilitySummary: String {
        let content = message.text.isEmpty && message.state == .responding ? "Thinking" : message.text
        let status = message.state == .stopped ? ". Response stopped" : message.state == .failed ? ". Reply incomplete" : ""
        return "\(message.role == .user ? "You" : "FitOut Coach"): \(content)\(status)"
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .assistant {
                    Text("FITOUT COACH").font(FitTheme.medium(10)).tracking(1.1)
                        .foregroundStyle(FitTheme.dashboardAccent)
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(FitTheme.body(15))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                } else if message.state == .responding {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(FitTheme.dashboardAccent)
                        Text("Thinking…").font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                    }
                }
                if message.state == .stopped || message.state == .failed {
                    Text(message.state == .stopped ? "Response stopped" : "Reply incomplete")
                        .font(FitTheme.medium(11)).foregroundStyle(FitTheme.textSecondary)
                }
            }
            .padding(14)
            .background(message.role == .user ? FitTheme.dashboardAccent.opacity(0.13) : FitTheme.surface,
                        in: RoundedRectangle(cornerRadius: 18))
            if message.role == .assistant { Spacer(minLength: 12) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }
}

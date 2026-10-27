import SwiftUI

struct CoachView: View {
    @Environment(\.appNavigationStyle) private var navigationStyle
    @Bindable var store: CoachStore
    let container: AppContainer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var followsLatest = true
    @State private var sheet: CoachSheet?

    private enum CoachSheet: String, Identifiable { case context, chats; var id: String { rawValue } }
    private var context: CoachContext { CoachContextBuilder.build(container: container) }

    init(container: AppContainer) { self.container = container; self.store = container.coach }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: FitTheme.sectionSpacing) {
                        if !store.availability.isAvailable { unavailableNotice }
                        if let error = store.storageError {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Chat storage needs attention", systemImage: "externaldrive.badge.exclamationmark").font(FitTheme.section(15))
                                Text(error).font(FitTheme.body(13))
                                Button { store.retryStorage() } label: { Text("Retry storage").frame(minHeight: 44).contentShape(Rectangle()) }
                            }.padding(FitTheme.cardInset).fitSurface(radius: 16)
                        }
                        if store.messages.isEmpty { welcome }
                        ForEach(store.messages) { message in
                            CoachMessageBubble(message: message)
                                .id(message.id)
                        }
                        if store.messages.last?.role == .assistant, store.messages.last?.state == .complete,
                           store.messages.last?.source == .model, !store.isResponding {
                            HStack(spacing: 12) {
                                refinement("More detail", question: "Give me concrete steps and an example for your last answer.")
                                refinement("Make it simpler", question: "Explain your last answer more simply, with one practical next step.")
                            }
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
        .foregroundStyle(FitTheme.textPrimary)
        .safeAreaInset(edge: .bottom, spacing: 0) { composer.workoutControlClearance("coach.composer") }
        .navigationTitle("AI Coach")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { store.refreshAvailability() }
        .onDisappear { store.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshAvailability() }
            else { store.stop() }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .context: CoachSharingView(container: container, store: store)
            case .chats: CoachHistoryView(store: store)
            }
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
            .padding(.trailing, navigationStyle == .topRight ? 68 : 0)
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(store.availability.isAvailable ? Color.green : FitTheme.textSecondary)
                        .frame(width: 5, height: 5)
                    Text(store.availability.isAvailable ? "ON-DEVICE" : "UNAVAILABLE")
                        .font(FitTheme.medium(10)).tracking(1.2)
                        .foregroundStyle(FitTheme.textSecondary)
                }
                Spacer()
                Button { sheet = .chats } label: { Image(systemName: "clock.arrow.circlepath").frame(width: 44, height: 44) }
                    .accessibilityLabel("Saved conversations")
                Button { store.newChat() } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }
                .buttonStyle(.fitPlain).disabled(!store.archiveLoaded || store.messages.isEmpty)
                .accessibilityLabel("New conversation")
                .accessibilityIdentifier("coachNewChat")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sharingButton; recordsButton }
                VStack(alignment: .leading, spacing: 0) { sharingButton; recordsButton }
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
            Text("Get specific exercise cues, build a session, or work through a meal. Share your records when you want a personal review.")
                .font(FitTheme.body(14))
                .foregroundStyle(FitTheme.textSecondary)
            VStack(spacing: 10) {
                starter("Plan a 30-minute full-body dumbbell workout with sets, reps and rest", symbol: "dumbbell")
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
        .buttonStyle(.fitPlain)
        .disabled(store.isResponding || !store.availability.isAvailable || !store.archiveLoaded)
    }

    private var sharingButton: some View {
        Button { sheet = .context } label: {
            Label(store.permissions.scopes.isEmpty ? "Choose context" : "Context · \(store.permissions.scopes.count) shared", systemImage: "slider.horizontal.3")
                .font(FitTheme.medium(12)).frame(minHeight: 44)
        }.accessibilityIdentifier("coachContext")
    }
    private var recordsButton: some View {
        Button {
            if store.permissions.scopes.isEmpty { sheet = .context }
            else { followsLatest = true; store.showRecords(context: context) }
        } label: {
            Label("My records", systemImage: "chart.bar.doc.horizontal").font(FitTheme.medium(12)).frame(minHeight: 44)
        }.disabled(store.isResponding || !store.archiveLoaded).accessibilityIdentifier("coachRecords")
    }
    private func refinement(_ label: String, question: String) -> some View {
        Button { store.draft = question; send() } label: {
            Text(label).font(FitTheme.medium(12)).padding(.horizontal, 14).frame(minHeight: 44).dashboardGlass(in: Capsule(), interactive: true)
        }.buttonStyle(.fitPlain).disabled(!store.availability.isAvailable || !store.archiveLoaded || store.isResponding)
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
                    .disabled(!store.availability.isAvailable || !store.archiveLoaded)
                    .accessibilityLabel("Message your fitness coach")
                    .accessibilityIdentifier("coachMessageInput")
                Button {
                    if store.isResponding { store.stop() }
                    else { send() }
                } label: {
                    Image(systemName: store.isResponding ? "stop.fill" : "arrow.up")
                        .font(.system(size: store.isResponding ? 15 : 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(FitTheme.dashboardAccent.opacity(store.isResponding || store.canSend ? 1 : 0.3), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.fitPlain)
                .disabled(!store.isResponding && !store.canSend)
                .accessibilityLabel(store.isResponding ? "Stop reply" : "Send message")
                .accessibilityIdentifier("coachSendOrStop")
            }
            if store.draft.count > 1_000 {
                Text("\(store.draft.count)/\(CoachConversation.maximumMessageLength) characters")
                    .font(FitTheme.medium(10))
                    .foregroundStyle(store.draft.count > CoachConversation.maximumMessageLength ? Color.orange : FitTheme.textSecondary)
            }
            Text("Saved on this iPhone · You control shared records. Units and age group guide safe answers.")
                .font(FitTheme.body(11))
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
        let author = message.role == .user ? "You" : message.source == .records ? "Your records, calculated" : "Coach, on-device AI"
        return "\(author): \(content)\(status)"
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .assistant {
                    Text(message.source == .records ? "Your records · Calculated" : "Coach · On-device AI").font(FitTheme.medium(11))
                        .foregroundStyle(FitTheme.dashboardAccent)
                }
                if !message.text.isEmpty {
                    Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
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
                if message.role == .assistant, !message.sharedScopes.isEmpty {
                    Text("Shared context: " + message.sharedScopes.map(\.title).joined(separator: ", "))
                        .font(FitTheme.body(11)).foregroundStyle(FitTheme.textSecondary)
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
        .contextMenu { if !message.text.isEmpty { Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text } } }
    }
}

private struct CoachSharingView: View {
    let container: AppContainer
    @Bindable var store: CoachStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(CoachScope.allCases) { scope in
                        Toggle(isOn: Binding(get: { store.permissions.includes(scope) }, set: { store.setPermission(scope, enabled: $0) })) {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(scope.title, systemImage: scope.symbol).font(FitTheme.section(15))
                                Text(scope.detail).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }.padding(.vertical, 4)
                        }.disabled(!store.archiveLoaded)
                    }
                } footer: {
                    Text("All sharing starts off. Turning a category off removes its previous context from future requests. Existing messages remain visible until you delete their conversation. No data leaves the device through this coach.")
                }
                Section("Preview of shared records") {
                    let facts = CoachContextBuilder.build(container: container).facts
                    if facts.isEmpty { Text("No app records shared. General fitness chat still works when AI is available.") }
                    ForEach(facts) { fact in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(fact.title).font(FitTheme.section(14))
                            Text(fact.detail).font(FitTheme.body(13)).foregroundStyle(FitTheme.textSecondary)
                        }.padding(.vertical, 4)
                    }
                }
                Section { Text("The coach can read a compact summary of selected records. It cannot change your routine, targets, meals or Health data. Suggestions must be reviewed and entered in the existing editors.").font(FitTheme.body(13)) }
            }.navigationTitle("Coach context").nutritionForm()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct CoachHistoryView: View {
    @Bindable var store: CoachStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: UUID?
    @State private var deletingAll = false
    var body: some View {
        NavigationStack {
            List {
                Button("New conversation", systemImage: "square.and.pencil") { store.newChat(); dismiss() }.disabled(!store.archiveLoaded)
                if let error = store.storageError {
                    Section { Text(error); Button("Retry storage") { store.retryStorage() } }
                }
                if store.chats.isEmpty { Text("Your conversations will appear here after the first message.").foregroundStyle(FitTheme.textSecondary) }
                ForEach(store.orderedChats) { chat in
                    Button { store.selectChat(chat.id); dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chat.title).font(FitTheme.section(14)).lineLimit(2)
                                Text(chat.updatedAt, format: .dateTime.month().day().hour().minute()).font(FitTheme.body(12)).foregroundStyle(FitTheme.textSecondary)
                            }
                            Spacer()
                            if store.selectedID == chat.id { Image(systemName: "checkmark").foregroundStyle(FitTheme.dashboardAccent) }
                        }.frame(minHeight: 44)
                    }.foregroundStyle(FitTheme.textPrimary)
                    .swipeActions { Button("Delete", role: .destructive) { deleting = chat.id } }
                }
                Section {
                    Button("Delete all chats & reset sharing", role: .destructive) { deletingAll = true }
                } footer: { Text("Deletes coach conversations only. Workout, nutrition, profile and Health data stay available.") }
            }.navigationTitle("Conversations").nutritionForm()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                    Button("Delete conversation", role: .destructive) { if let deleting { store.deleteChat(deleting) }; deleting = nil }
                }
                .confirmationDialog("Delete all coach history?", isPresented: $deletingAll, titleVisibility: .visible) {
                    Button("Delete all chats", role: .destructive) { store.clear() }
                } message: { Text("This removes saved coach conversations from this iPhone and turns context sharing off. It cannot be undone.") }
        }
    }
}

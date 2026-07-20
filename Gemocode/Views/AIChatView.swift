import SwiftUI

/// "Ask about your report" — a lightweight chat surface over an already
/// generated `HealthReview`. Conversation state is view-local only: nothing
/// is written to SwiftData or UserDefaults, and only the visible messages
/// plus a compact text summary of the review (built by
/// `AIChatService.buildContext`) are ever sent to the network. Presented as
/// a sheet from `ReviewScreen`.
struct AIChatView: View {
    let review: HealthReview
    let profileSummary: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var messages: [AIChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var context: String {
        AIChatService.buildContext(review: review, profileSummary: profileSummary)
    }

    /// Whether any finding in this review looks like a medication
    /// interaction — if so, `MedicationInteractions.disclaimer` is surfaced
    /// alongside the standard chat footer.
    private var hasInteractionFinding: Bool {
        review.findings.contains {
            $0.category == .medications && $0.title.localizedCaseInsensitiveContains("interaction")
        }
    }

    private static let starterQuestions = [
        String(localized: "What does my score mean?"),
        String(localized: "Which finding should I focus on first?"),
        String(localized: "What should I ask my doctor?")
    ]

    var body: some View {
        NavigationStack {
            Group {
                if !AISummaryService.isConfigured {
                    unconfiguredState
                } else {
                    chatContent
                }
            }
            .background(AmbientBackground().accessibilityHidden(true))
            .navigationTitle("Ask About Your Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Unconfigured state

    private var unconfiguredState: some View {
        ContentUnavailableView {
            Label("AI Chat Needs a Key", systemImage: "key.slash")
        } description: {
            Text("Add your Anthropic API key in Profile & Settings to ask questions about your health review.")
        }
    }

    // MARK: Chat content

    private var chatContent: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if messages.isEmpty {
                            starterChips
                        }
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if isLoading {
                            TypingIndicatorBubble()
                                .id("typing")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: isLoading) { _, _ in
                    scrollToBottom(proxy)
                }
            }

            if let errorMessage {
                errorRow(errorMessage)
            }

            footerDisclaimer

            inputBar
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if isLoading {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: Starter chips

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try asking:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Self.starterQuestions, id: \.self) { question in
                Button {
                    send(text: question)
                } label: {
                    Text(question)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Error row

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss error")
        }
        .padding(10)
        .tintedGlassCard(.orange)
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: Footer

    private var footerDisclaimer: some View {
        VStack(spacing: 2) {
            Text("Educational, not medical advice. Only your review summary is sent — never your documents.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if hasInteractionFinding {
                Text(MedicationInteractions.disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask a question…", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Glass.bevelStroke(for: colorScheme), lineWidth: 1))
                .disabled(isLoading)

            Button {
                send(text: inputText)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Glass.accentGradient, in: Circle())
            }
            .accessibilityLabel("Send message")
            .disabled(isLoading || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }

    // MARK: Sending

    private func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isLoading else { return }

        errorMessage = nil
        inputText = ""
        messages.append(AIChatMessage(role: .user, text: trimmed))

        isLoading = true
        let history = messages
        let currentContext = context
        Task {
            do {
                let replyText = try await AIChatService.reply(history: history, context: currentContext)
                messages.append(AIChatMessage(role: .assistant, text: replyText))
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: AIChatMessage

    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool { message.role == .user }

    var body: some View {
        Group {
            if isUser {
                HStack {
                    Spacer(minLength: 40)
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(Editorial.ink(colorScheme))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .background(Editorial.insetCard(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            } else {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Editorial.ink(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ledgerRow()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(isUser ? String(localized: "You") : String(localized: "Assistant")) said: \(message.text)"
        )
    }
}

// MARK: - Typing indicator

private struct TypingIndicatorBubble: View {
    @State private var animate = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Editorial.muted(colorScheme))
                    .frame(width: 6, height: 6)
                    .opacity(animate ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.15),
                        value: animate
                    )
            }
            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Assistant is typing")
        .onAppear { animate = true }
    }
}

import SwiftUI
import UIKit

struct ChatView: View {
    let conversation: Conversation

    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var selectedUserMessageID: UUID?
    @State private var feedbackStates: [UUID: UserMessageFeedbackState] = [:]

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(chatStore.messages(for: conversation)) { message in
                                VStack(spacing: 8) {
                                    MessageBubbleView(
                                        message: message,
                                        isSelected: message.role == .user && selectedUserMessageID == message.id
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleMessageTap(message)
                                    }

                                    if message.role == .user,
                                       selectedUserMessageID == message.id,
                                       let state = feedbackStates[message.id] {
                                        UserMessageFeedbackCard(
                                            originalText: message.text,
                                            state: state
                                        )
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 90)
                    }
                    .onAppear {
                        chatStore.markConversationOpened(conversation)
                        scrollToBottom(proxy)
                    }
                    .onChange(of: chatStore.messages(for: conversation).map(\.id)) { _ in
                        scrollToBottom(proxy)
                    }
                }
            }

            inputBar
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 28, height: 28)
            }

            Spacer()

            VStack(spacing: 2) {
                Text(conversation.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Gemini 3 Flash")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.blue)
                    .frame(width: 28, height: 28)
            }
            .opacity(0.9)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("iMessage", text: $messageText, axis: .vertical)
                .font(.system(size: 18))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .lineLimit(1...4)
                .background(Color(uiColor: .systemBackground))
                .clipShape(Capsule())

            Button(action: sendMessage) {
                Image(systemName: sendButtonSymbol)
                    .font(.system(size: 22))
                    .foregroundStyle(sendButtonColor)
                    .frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var sendButtonSymbol: String {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up.circle.fill"
    }

    private var sendButtonColor: Color {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .blue
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatStore.sendUserMessage(trimmed, in: conversation)
        messageText = ""
    }

    private func handleMessageTap(_ message: ChatMessage) {
        guard message.role == .user else { return }

        if selectedUserMessageID == message.id {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedUserMessageID = nil
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.18)) {
            selectedUserMessageID = message.id
        }

        if case .some(.loaded(_)) = feedbackStates[message.id] {
            return
        }
        if case .some(.loading) = feedbackStates[message.id] {
            return
        }

        feedbackStates[message.id] = .loading
        Task {
            do {
                let response = try await BackendAPIClient.shared.grammarFeedback(text: message.text)
                await MainActor.run {
                    feedbackStates[message.id] = .loaded(response)
                }
            } catch {
                await MainActor.run {
                    feedbackStates[message.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = chatStore.messages(for: conversation).last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

private enum UserMessageFeedbackState {
    case loading
    case loaded(GrammarFeedbackResponse)
    case failed(String)
}

private struct UserMessageFeedbackCard: View {
    let originalText: String
    let state: UserMessageFeedbackState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("YOUR MESSAGE")
            originalMessageBox

            sectionLabel("NATIVE FEEDBACK")
            feedbackBody

            if case let .loaded(data) = state,
               data.hasErrors,
               !data.correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sectionLabel("CORRECTED SENTENCE")
                Text(data.correctedText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
            }

            if case let .loaded(data) = state,
               !data.naturalAlternative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sectionLabel("MORE NATURAL WAY")
                VStack(alignment: .leading, spacing: 6) {
                    Text(data.naturalAlternative)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if !data.naturalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(data.naturalReason)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.blue.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.blue.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var originalMessageBox: some View {
        Group {
            if case let .loaded(data) = state {
                highlightedOriginalMessageText(highlights: highlightTerms(from: data))
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
            } else {
                Text(originalText)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var feedbackBody: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking your sentence...")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)

        case let .failed(message):
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

        case let .loaded(data):
            VStack(alignment: .leading, spacing: 8) {
                Text(data.feedback)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                if !data.feedbackPoints.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(data.feedbackPoints.enumerated()), id: \.offset) { _, point in
                            feedbackPointRow(point)
                        }
                    }
                } else if !data.hasErrors {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.green)
                        Text("No grammar issues.")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                }

                if !data.naturalRewrite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Natural rewrite")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(data.naturalRewrite)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func highlightTerms(from data: GrammarFeedbackResponse) -> [String] {
        let fromPoints = data.feedbackPoints.map { $0.part }
        let fromEdits = data.edits.map { $0.wrong }
        let all = (fromPoints + fromEdits)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }

        var result: [String] = []
        var seen = Set<String>()
        for item in all {
            let key = item.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }

    private func highlightedOriginalMessageText(highlights: [String]) -> Text {
        let source = originalText
        guard !source.isEmpty, !highlights.isEmpty else { return Text(source) }

        let nsSource = source as NSString
        var matches: [NSRange] = []

        for term in highlights {
            guard !term.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: term)
            guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else { continue }
            let found = regex.matches(in: source, options: [], range: NSRange(location: 0, length: nsSource.length))
            matches.append(contentsOf: found.map(\.range))
        }

        if matches.isEmpty { return Text(source) }

        matches.sort { a, b in
            if a.location == b.location { return a.length > b.length }
            return a.location < b.location
        }

        var nonOverlapping: [NSRange] = []
        var lastEnd = 0
        for range in matches {
            guard range.location >= lastEnd else { continue }
            nonOverlapping.append(range)
            lastEnd = range.location + range.length
        }

        var text = Text("")
        var cursor = 0
        for range in nonOverlapping {
            if range.location > cursor {
                let prefix = nsSource.substring(with: NSRange(location: cursor, length: range.location - cursor))
                text = text + Text(prefix)
            }
            let matched = nsSource.substring(with: range)
            text = text + Text(matched).foregroundColor(.red).fontWeight(.semibold)
            cursor = range.location + range.length
        }
        if cursor < nsSource.length {
            let suffix = nsSource.substring(with: NSRange(location: cursor, length: nsSource.length - cursor))
            text = text + Text(suffix)
        }
        return text
    }

    private func feedbackPointRow(_ point: GrammarFeedbackResponse.GrammarFeedbackPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(point.part)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                Text("→")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text((point.fix ?? "").isEmpty ? "(improve)" : (point.fix ?? ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
            }
            if let issue = point.issue, !issue.isEmpty {
                Text(issue)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: SampleData.conversations[0])
            .environmentObject(ChatStore())
    }
}

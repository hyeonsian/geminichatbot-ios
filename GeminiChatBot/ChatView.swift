import SwiftUI
import UIKit

struct ChatView: View {
    let conversation: Conversation

    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var selectedUserMessageID: UUID?
    @State private var feedbackStates: [UUID: UserMessageFeedbackState] = [:]
    @State private var nativeAlternativesStates: [UUID: NativeAlternativesLoadState] = [:]
    @State private var nativeAlternativesSheetMessage: ChatMessage?
    @State private var aiTranslationStates: [UUID: AIMessageTranslationState] = [:]
    @State private var isSearchVisible = false
    @State private var searchQuery = ""
    @State private var selectedSearchResultIndex = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        if isSearchVisible {
                            searchBar(proxy: proxy)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(chatStore.messages(for: conversation)) { message in
                                    messageRow(message)
                                        .id(message.id)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 90)
                        }
                        .onAppear {
                            chatStore.markConversationOpened(conversation)
                            syncSearchSelection()
                            scrollToBottom(proxy)
                        }
                        .onChange(of: chatStore.messages(for: conversation).map(\.id)) { _ in
                            syncSearchSelection()
                            if isSearchVisible, selectedSearchMatchMessageID != nil {
                                scrollToSelectedSearchResult(proxy)
                            } else {
                                scrollToBottom(proxy)
                            }
                        }
                        .onChange(of: searchQuery) { _ in
                            syncSearchSelection()
                            if isSearchVisible {
                                scrollToSelectedSearchResult(proxy)
                            }
                        }
                        .onChange(of: isSearchVisible) { visible in
                            if !visible {
                                searchQuery = ""
                                selectedSearchResultIndex = 0
                            } else {
                                syncSearchSelection()
                                scrollToSelectedSearchResult(proxy)
                            }
                        }
                    }
                }
            }

            inputBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $nativeAlternativesSheetMessage) { message in
            NativeAlternativesSheet(
                originalText: message.text,
                state: nativeAlternativesStates[message.id] ?? .loading,
                isAlreadySaved: { item in
                    chatStore.isSavedDictionaryText(item.text)
                },
                onSaveOption: { item in
                    chatStore.saveNativeAlternative(item, originalText: message.text)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var searchMatchMessageIDs: [UUID] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return chatStore.messages(for: conversation)
            .filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
            .map(\.id)
    }

    private var selectedSearchMatchMessageID: UUID? {
        guard !searchMatchMessageIDs.isEmpty else { return nil }
        let safeIndex = min(max(selectedSearchResultIndex, 0), searchMatchMessageIDs.count - 1)
        return searchMatchMessageIDs[safeIndex]
    }

    @ViewBuilder
    private func searchBar(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search messages", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 15))

                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            selectedSearchResultIndex = 0
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                Text(searchResultCounterText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 40)

                Button(action: { moveSearchSelection(-1, proxy: proxy) }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(searchMatchMessageIDs.isEmpty ? .secondary : Color.blue)
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Circle())
                }
                .disabled(searchMatchMessageIDs.isEmpty)

                Button(action: { moveSearchSelection(1, proxy: proxy) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(searchMatchMessageIDs.isEmpty ? .secondary : Color.blue)
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(Circle())
                }
                .disabled(searchMatchMessageIDs.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .background(Color(uiColor: .systemBackground))

            Divider()
        }
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

            Button(action: toggleSearchVisibility) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.blue)
                    .frame(width: 28, height: 28)
            }
            .contentTransition(.symbolEffect(.replace))
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

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        let matched = searchMatchMessageIDs.contains(message.id)
        let activeMatched = selectedSearchMatchMessageID == message.id
        let isSelectedUserMessage = message.role == .user && selectedUserMessageID == message.id

        VStack(spacing: 8) {
            if isSelectedUserMessage, let state = feedbackStates[message.id] {
                HStack {
                    Spacer(minLength: 54)
                    UserMessageFeedbackCard(
                        originalText: message.text,
                        state: state,
                        nativeAlternativesState: nativeAlternativesStates[message.id] ?? .idle,
                        onTapNativeAlternatives: {
                            openNativeAlternatives(for: message)
                        }
                    )
                    .frame(maxWidth: 320, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        handleMessageTap(message)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                MessageBubbleView(
                    message: message,
                    isSelected: false,
                    highlightQuery: searchQuery,
                    isSearchMatched: matched,
                    isActiveSearchMatch: activeMatched,
                    translatedText: translationVisibleText(for: message),
                    translationError: translationErrorText(for: message),
                    isTranslationLoading: isTranslationLoading(for: message),
                    onTapTranslate: message.role == .ai ? { toggleAITranslation(for: message) } : nil
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleMessageTap(message)
        }
    }

    private func toggleSearchVisibility() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearchVisible.toggle()
        }
    }

    private func toggleAITranslation(for message: ChatMessage) {
        guard message.role == .ai else { return }

        switch aiTranslationStates[message.id] ?? .idle {
        case .shown(let text):
            withAnimation(.easeInOut(duration: 0.22)) {
                aiTranslationStates[message.id] = .hidden(text)
            }
            return
        case .hidden(let text):
            withAnimation(.easeInOut(duration: 0.22)) {
                aiTranslationStates[message.id] = .shown(text)
            }
            return
        case .loading:
            return
        case .failed:
            break
        case .idle:
            break
        }

        aiTranslationStates[message.id] = .loading

        Task {
            do {
                let translation = try await BackendAPIClient.shared.translate(text: message.text, targetLang: "Korean")
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        aiTranslationStates[message.id] = .shown(translation)
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        aiTranslationStates[message.id] = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func isTranslationLoading(for message: ChatMessage) -> Bool {
        guard message.role == .ai else { return false }
        if case .loading = aiTranslationStates[message.id] { return true }
        return false
    }

    private func translationVisibleText(for message: ChatMessage) -> String? {
        guard message.role == .ai else { return nil }
        if case let .shown(text) = aiTranslationStates[message.id] {
            return text
        }
        return nil
    }

    private func translationErrorText(for message: ChatMessage) -> String? {
        guard message.role == .ai else { return nil }
        if case let .failed(text) = aiTranslationStates[message.id] {
            return text
        }
        return nil
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

    private var searchResultCounterText: String {
        guard !searchMatchMessageIDs.isEmpty else { return "0/0" }
        return "\(selectedSearchResultIndex + 1)/\(searchMatchMessageIDs.count)"
    }

    private func syncSearchSelection() {
        if searchMatchMessageIDs.isEmpty {
            selectedSearchResultIndex = 0
            return
        }
        if selectedSearchResultIndex >= searchMatchMessageIDs.count {
            selectedSearchResultIndex = searchMatchMessageIDs.count - 1
        }
        if selectedSearchResultIndex < 0 {
            selectedSearchResultIndex = 0
        }
    }

    private func moveSearchSelection(_ delta: Int, proxy: ScrollViewProxy) {
        guard !searchMatchMessageIDs.isEmpty else { return }
        let count = searchMatchMessageIDs.count
        selectedSearchResultIndex = (selectedSearchResultIndex + delta + count) % count
        scrollToSelectedSearchResult(proxy)
    }

    private func scrollToSelectedSearchResult(_ proxy: ScrollViewProxy) {
        guard let targetID = selectedSearchMatchMessageID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    private func openNativeAlternatives(for message: ChatMessage) {
        guard message.role == .user else { return }
        nativeAlternativesSheetMessage = message

        if case .some(.loaded(_)) = nativeAlternativesStates[message.id] {
            return
        }
        if case .some(.loading) = nativeAlternativesStates[message.id] {
            return
        }

        nativeAlternativesStates[message.id] = .loading

        Task {
            do {
                let items = try await BackendAPIClient.shared.nativeAlternatives(text: message.text)
                let preferred = preferredNativeAlternative(from: feedbackStates[message.id])
                let merged = mergeNativeAlternatives(items, preferred: preferred)
                await MainActor.run {
                    nativeAlternativesStates[message.id] = .loaded(merged)
                }
            } catch {
                await MainActor.run {
                    nativeAlternativesStates[message.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func preferredNativeAlternative(from state: UserMessageFeedbackState?) -> NativeAlternativeItem? {
        guard case let .some(.loaded(data)) = state else { return nil }
        let text = data.naturalAlternative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let nuance = data.naturalReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return NativeAlternativeItem(
            text: text,
            tone: "Most Common",
            nuance: nuance.isEmpty ? "Simple everyday phrasing" : nuance
        )
    }

    private func mergeNativeAlternatives(
        _ items: [NativeAlternativeItem],
        preferred: NativeAlternativeItem?
    ) -> [NativeAlternativeItem] {
        var merged: [NativeAlternativeItem] = []
        var seen = Set<String>()

        func appendIfNeeded(_ item: NativeAlternativeItem?) {
            guard let item else { return }
            let key = item.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
                .lowercased()
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            merged.append(item)
        }

        appendIfNeeded(preferred)
        items.forEach { appendIfNeeded($0) }
        return Array(merged.prefix(3))
    }
}

private enum UserMessageFeedbackState {
    case loading
    case loaded(GrammarFeedbackResponse)
    case failed(String)
}

private enum NativeAlternativesLoadState {
    case idle
    case loading
    case loaded([NativeAlternativeItem])
    case failed(String)
}

private enum AIMessageTranslationState {
    case idle
    case loading
    case shown(String)
    case hidden(String)
    case failed(String)
}

private struct UserMessageFeedbackCard: View {
    let originalText: String
    let state: UserMessageFeedbackState
    let nativeAlternativesState: NativeAlternativesLoadState
    let onTapNativeAlternatives: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("YOUR MESSAGE")
            originalMessageBox

            sectionLabel("NATIVE FEEDBACK")
            feedbackBody

            if case let .loaded(data) = state,
               let improved = improvedExpression(from: data),
               !improved.isEmpty {
                sectionLabel("IMPROVED EXPRESSION")
                Text(improved)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.blue.opacity(0.12), lineWidth: 1)
                    )
            }

            nativeAlternativesButton
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

    private var nativeAlternativesButton: some View {
        Button(action: onTapNativeAlternatives) {
            HStack(spacing: 8) {
                if case .loading = nativeAlternativesState {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(nativeAlternativesButtonLabel)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled({
            if case .loading = nativeAlternativesState { return true }
            return false
        }())
    }

    private var nativeAlternativesButtonLabel: String {
        switch nativeAlternativesState {
        case .idle:
            return "Native alternatives"
        case .loading:
            return "Loading alternatives..."
        case .loaded:
            return "Open native alternatives"
        case .failed:
            return "Retry native alternatives"
        }
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
                Text(feedbackFixPreview(for: point))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.green)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
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

    private func feedbackFixPreview(for point: GrammarFeedbackResponse.GrammarFeedbackPoint) -> String {
        let raw = (point.fix ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized = normalizedReplacement(from: raw, part: point.part) {
            return normalized
        }
        return raw.isEmpty ? "(improve)" : raw
    }

    private func improvedExpression(from data: GrammarFeedbackResponse) -> String? {
        let source = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        var candidates: [String] = []

        if data.hasErrors {
            let corrected = data.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !corrected.isEmpty && !isMinorSentenceDifference(source, corrected) {
                candidates.append(corrected)
            }
        }

        let viaEdits = applyEdits(source, edits: data.edits)
        let viaPoints = applyFeedbackPoints(viaEdits, points: data.feedbackPoints)
        if !viaPoints.isEmpty && !isMinorSentenceDifference(source, viaPoints) {
            candidates.append(viaPoints)
        }

        let naturalRewrite = data.naturalRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        if !naturalRewrite.isEmpty && !isMinorSentenceDifference(source, naturalRewrite) {
            candidates.append(naturalRewrite)
        }

        let naturalAlternative = data.naturalAlternative.trimmingCharacters(in: .whitespacesAndNewlines)
        if !naturalAlternative.isEmpty && !isMinorSentenceDifference(source, naturalAlternative) {
            candidates.append(naturalAlternative)
        }

        var seen = Set<String>()
        for item in candidates {
            let key = normalizedTextKey(item)
            if key.isEmpty || seen.contains(key) { continue }
            seen.insert(key)
            return item
        }
        return nil
    }

    private func applyEdits(_ source: String, edits: [GrammarFeedbackResponse.GrammarEdit]) -> String {
        var text = source
        let sorted = edits.sorted { $0.wrong.count > $1.wrong.count }
        for edit in sorted {
            let wrong = edit.wrong.trimmingCharacters(in: .whitespacesAndNewlines)
            let right = edit.right.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wrong.isEmpty, !right.isEmpty else { continue }
            text = replacingFirstCaseInsensitive(in: text, target: wrong, replacement: right)
        }
        return text
    }

    private func applyFeedbackPoints(_ source: String, points: [GrammarFeedbackResponse.GrammarFeedbackPoint]) -> String {
        var text = source
        let sorted = points.sorted { $0.part.count > $1.part.count }
        for point in sorted {
            let part = point.part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { continue }
            guard let replacement = normalizedReplacement(from: point.fix ?? "", part: part) else { continue }
            if normalizedTextKey(replacement).isEmpty { continue }
            text = replacingFirstCaseInsensitive(in: text, target: part, replacement: replacement)
        }
        return text
    }

    private func normalizedReplacement(from rawFix: String, part: String) -> String? {
        let raw = rawFix.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        if let addQuoted = firstQuotedPhrase(in: raw, afterPrefix: "add") {
            let merged = "\(part) \(addQuoted)".replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            return merged.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let useQuoted = firstQuotedPhrase(in: raw, afterPrefix: "use") {
            return useQuoted
        }

        if raw.count <= 36 {
            return raw
        }
        return nil
    }

    private func firstQuotedPhrase(in text: String, afterPrefix prefix: String) -> String? {
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: prefix) + "\\b\\s+['\\\"]([^'\\\"]+)['\\\"]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        let quoted = (text as NSString).substring(with: match.range(at: 1))
        return quoted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacingFirstCaseInsensitive(in source: String, target: String, replacement: String) -> String {
        guard !target.isEmpty else { return source }
        let escaped = NSRegularExpression.escapedPattern(for: target)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else { return source }
        let range = NSRange(location: 0, length: (source as NSString).length)
        guard let match = regex.firstMatch(in: source, options: [], range: range) else { return source }
        let ns = source as NSString
        let result = ns.replacingCharacters(in: match.range, with: replacement)
        return result
    }

    private func normalizedTextKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func isMinorSentenceDifference(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTextKey(lhs) == normalizedTextKey(rhs)
    }
}

private struct NativeAlternativesSheet: View {
    let originalText: String
    let state: NativeAlternativesLoadState
    let isAlreadySaved: (NativeAlternativeItem) -> Bool
    let onSaveOption: (NativeAlternativeItem) -> Bool
    @State private var locallySavedKeys: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("YOUR MESSAGE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)
                        Text(originalText)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("NATIVE ALTERNATIVES")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        content
                    }
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Native alternatives")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Generating natural alternatives...")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

        case let .failed(message):
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

        case let .loaded(items):
            VStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Option \(index + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(item.tone)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.blue)
                        }

                        Text(item.text)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary)

                        Text(item.nuance)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        HStack {
                            Spacer()
                            Button(action: {
                                let key = normalizedKey(item.text)
                                if onSaveOption(item) || isAlreadySaved(item) {
                                    locallySavedKeys.insert(key)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: savedState(for: item) ? "checkmark" : "plus")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(savedState(for: item) ? "Saved" : "Save to My Dictionary")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(savedState(for: item) ? Color.green : Color.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.blue.opacity(0.10), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func normalizedKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            .lowercased()
    }

    private func savedState(for item: NativeAlternativeItem) -> Bool {
        let key = normalizedKey(item.text)
        return locallySavedKeys.contains(key) || isAlreadySaved(item)
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: SampleData.conversations[0])
            .environmentObject(ChatStore())
    }
}

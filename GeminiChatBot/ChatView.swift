import SwiftUI
import UIKit
import AVFoundation

private final class ChatAudioPlayerDelegateProxy: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?
    var onDecodeError: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onDecodeError?()
    }
}

struct ChatView: View {
    let conversation: Conversation

    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var selectedUserMessageID: UUID?
    @State private var feedbackStates: [UUID: UserMessageFeedbackState] = [:]
    @State private var nativeAlternativesStates: [UUID: NativeAlternativesLoadState] = [:]
    @State private var nativeAlternativesSheetMessage: ChatMessage?
    @State private var pendingGrammarSaveRequest: PendingGrammarSaveRequest?
    @State private var aiTranslationStates: [UUID: AIMessageTranslationState] = [:]
    @State private var aiSpeechLoadingMessageIDs: Set<UUID> = []
    @State private var activeAISpeechMessageID: UUID?
    @State private var aiSpeechAudioCache: [UUID: Data] = [:]
    @State private var aiSpeechPlayer: AVAudioPlayer?
    @State private var audioPlayerDelegateProxy = ChatAudioPlayerDelegateProxy()
    @State private var isSearchVisible = false
    @State private var searchQuery = ""
    @State private var selectedSearchResultIndex = 0
    @State private var showProfileEditor = false
    @StateObject private var speechToText = SpeechToTextService(localeIdentifier: "en-US")
    @State private var speechInputAlertMessage: String?

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
        .onDisappear {
            stopAISpeechPlayback()
            speechToText.stopRecording()
        }
        .onChange(of: speechToText.transcript) { transcript in
            if speechToText.isRecording || !transcript.isEmpty {
                messageText = transcript
            }
        }
        .onChange(of: speechToText.errorMessage) { errorMessage in
            guard let errorMessage, !errorMessage.isEmpty else { return }
            speechInputAlertMessage = errorMessage
        }
        .onChange(of: currentAIProfile.koreanTranslationSpeechLevel) { _ in
            aiTranslationStates.removeAll()
        }
        .alert("Speech Input", isPresented: Binding(
            get: { speechInputAlertMessage != nil },
            set: { isPresented in
                if !isPresented { speechInputAlertMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {
                speechInputAlertMessage = nil
            }
        } message: {
            Text(speechInputAlertMessage ?? "")
        }
        .navigationDestination(isPresented: $showProfileEditor) {
            AIProfileEditorView(conversationID: conversation.id)
                .environmentObject(chatStore)
        }
        .sheet(item: $nativeAlternativesSheetMessage) { message in
            NativeAlternativesSheet(
                originalText: message.text,
                state: nativeAlternativesStates[message.id] ?? .loading,
                availableCategories: chatStore.dictionaryCategories,
                isAlreadySaved: { item in
                    chatStore.isSavedDictionaryText(item.text)
                },
                onCreateCategory: { name in
                    chatStore.createDictionaryCategory(named: name)
                },
                onSaveOption: { item, categoryIDs in
                    chatStore.saveNativeAlternative(item, originalText: message.text, categoryIDs: categoryIDs)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $pendingGrammarSaveRequest) { request in
            GrammarCorrectionCategoryPickerSheet(
                correctedText: request.correctedText,
                originalText: request.originalText,
                categories: chatStore.dictionaryCategories,
                isAlreadySaved: chatStore.isSavedDictionaryText(request.correctedText),
                onCreateCategory: { name in
                    chatStore.createDictionaryCategory(named: name)
                },
                onSave: { selectedCategoryIDs in
                    _ = chatStore.saveGrammarCorrection(
                        request.correctedText,
                        originalText: request.originalText,
                        categoryIDs: selectedCategoryIDs,
                        corrections: request.corrections
                    )
                },
                onSaveWithoutCategory: {
                    _ = chatStore.saveGrammarCorrection(
                        request.correctedText,
                        originalText: request.originalText,
                        corrections: request.corrections
                    )
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

            Button(action: { showProfileEditor = true }) {
                VStack(spacing: 2) {
                    headerAvatar

                    Text(currentAIProfile.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Gemini 3 Flash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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

    @ViewBuilder
    private var headerAvatar: some View {
        if let data = currentAIProfile.avatarImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.45), Color.indigo.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(String((currentAIProfile.name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "A")).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
        }
    }

    private var currentAIProfile: AIProfileSettings {
        chatStore.aiProfile(for: conversation)
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

            Button(action: handlePrimaryInputAction) {
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
        if speechToText.isRecording { return "stop.circle.fill" }
        return messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "mic.fill" : "arrow.up.circle.fill"
    }

    private var sendButtonColor: Color {
        if speechToText.isRecording { return Color.red }
        return messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.blue
    }

    private func handlePrimaryInputAction() {
        if speechToText.isRecording {
            speechToText.stopRecording()
            return
        }

        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            speechToText.startRecording(initialText: "")
            return
        }

        sendMessage()
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speechToText.stopRecording()
        chatStore.sendUserMessage(trimmed, in: conversation)
        messageText = ""
        speechToText.clearTranscript()
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
                        isImprovedExpressionSaved: isImprovedExpressionSaved(for: message),
                        onSaveImprovedExpression: { improvedText in
                            presentGrammarCorrectionCategoryPicker(
                                correctedText: improvedText,
                                originalText: message.text,
                                corrections: grammarCorrectionPairsForMessage(message)
                            )
                        },
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
                    onTapTranslate: message.role == .ai ? { toggleAITranslation(for: message) } : nil,
                    onTapSpeak: message.role == .ai ? { toggleAISpeech(for: message) } : nil,
                    isSpeechLoading: isAISpeechLoading(for: message),
                    isSpeaking: isAISpeaking(for: message)
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleMessageTap(message)
        }
    }

    private func isImprovedExpressionSaved(for message: ChatMessage) -> Bool {
        guard message.role == .user else { return false }
        guard let improved = improvedExpressionForMessage(message), !improved.isEmpty else { return false }
        return chatStore.isSavedDictionaryText(improved)
    }

    private func presentGrammarCorrectionCategoryPicker(
        correctedText: String,
        originalText: String,
        corrections: [DictionaryEntry.GrammarCorrectionPair]
    ) {
        pendingGrammarSaveRequest = PendingGrammarSaveRequest(
            correctedText: correctedText,
            originalText: originalText,
            corrections: corrections
        )
    }

    private func improvedExpressionForMessage(_ message: ChatMessage) -> String? {
        guard case let .loaded(data) = feedbackStates[message.id] else { return nil }
        let source = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return nil }

        let corrected = data.correctedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if data.hasErrors, !corrected.isEmpty, !isMinorSentenceDifference(source, corrected) {
            return corrected
        }

        let naturalRewrite = data.naturalRewrite.trimmingCharacters(in: .whitespacesAndNewlines)
        if !naturalRewrite.isEmpty, !isMinorSentenceDifference(source, naturalRewrite) {
            return naturalRewrite
        }

        let naturalAlternative = data.naturalAlternative.trimmingCharacters(in: .whitespacesAndNewlines)
        if !naturalAlternative.isEmpty, !isMinorSentenceDifference(source, naturalAlternative) {
            return naturalAlternative
        }

        return nil
    }

    private func grammarCorrectionPairsForMessage(_ message: ChatMessage) -> [DictionaryEntry.GrammarCorrectionPair] {
        guard case let .loaded(data) = feedbackStates[message.id] else { return [] }

        var pairs: [DictionaryEntry.GrammarCorrectionPair] = []
        var seen = Set<String>()

        for point in data.feedbackPoints {
            let wrong = point.part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wrong.isEmpty else { continue }
            guard let replacement = normalizedReplacement(from: point.fix ?? "", part: wrong), !replacement.isEmpty else { continue }
            guard !isMinorSentenceDifference(wrong, replacement) else { continue }
            let key = normalizedSentenceKey(wrong) + "->" + normalizedSentenceKey(replacement)
            if seen.contains(key) { continue }
            seen.insert(key)
            let reasonText = point.issue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let reason = (reasonText?.isEmpty == false) ? reasonText : nil
            pairs.append(.init(wrong: wrong, right: replacement, reason: reason))
        }

        if pairs.isEmpty {
            for edit in data.edits {
                let wrong = edit.wrong.trimmingCharacters(in: .whitespacesAndNewlines)
                let right = edit.right.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !wrong.isEmpty, !right.isEmpty else { continue }
                guard !isMinorSentenceDifference(wrong, right) else { continue }
                let key = normalizedSentenceKey(wrong) + "->" + normalizedSentenceKey(right)
                if seen.contains(key) { continue }
                seen.insert(key)
                let reasonText = edit.reason?.trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = (reasonText?.isEmpty == false) ? reasonText : nil
                pairs.append(.init(wrong: wrong, right: right, reason: reason))
            }
        }

        return pairs
    }

    private func normalizedSentenceKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func isMinorSentenceDifference(_ lhs: String, _ rhs: String) -> Bool {
        normalizedSentenceKey(lhs) == normalizedSentenceKey(rhs)
    }

    private func normalizedTextKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
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

        if let removeQuoted = firstQuotedPhrase(in: raw, afterPrefix: "remove")
            ?? firstQuotedPhrase(in: raw, afterPrefix: "delete")
            ?? firstQuotedPhrase(in: raw, afterPrefix: "omit") {
            if let removed = removingQuotedPhrase(removeQuoted, from: part) {
                return removed
            }
        }

        if raw.count <= 36 {
            return raw
        }
        return nil
    }

    private func firstQuotedPhrase(in text: String, afterPrefix prefix: String) -> String? {
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: prefix) + "\\b\\s+['\"]([^'\"]+)['\"]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else { return nil }
        let quoted = (text as NSString).substring(with: match.range(at: 1))
        return quoted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removingQuotedPhrase(_ quoted: String, from part: String) -> String? {
        let removed = replacingFirstCaseInsensitive(in: part, target: quoted, replacement: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,?.!])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !removed.isEmpty else { return nil }
        return removed
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
}

private struct PendingGrammarSaveRequest: Identifiable {
    let id = UUID()
    let correctedText: String
    let originalText: String
    let corrections: [DictionaryEntry.GrammarCorrectionPair]
}

private struct NativeAlternativesSheet: View {
    let originalText: String
    let state: NativeAlternativesLoadState
    let availableCategories: [DictionaryCategory]
    let isAlreadySaved: (NativeAlternativeItem) -> Bool
    let onCreateCategory: (String) -> DictionaryCategory?
    let onSaveOption: (NativeAlternativeItem, [UUID]) -> Bool
    @State private var locallySavedKeys: Set<String> = []
    @State private var pendingSaveItem: NativeAlternativeItem?
    @State private var isCategoryPickerPresented = false

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
        .sheet(isPresented: $isCategoryPickerPresented) {
            if let pendingSaveItem {
                NativeAlternativeCategoryPickerSheet(
                    item: pendingSaveItem,
                    categories: availableCategories,
                    onCreateCategory: onCreateCategory,
                    onSave: { selectedCategoryIDs in
                        let key = normalizedKey(pendingSaveItem.text)
                        if onSaveOption(pendingSaveItem, selectedCategoryIDs) || isAlreadySaved(pendingSaveItem) {
                            locallySavedKeys.insert(key)
                        }
                        isCategoryPickerPresented = false
                        self.pendingSaveItem = nil
                    },
                    onSaveWithoutCategory: {
                        let key = normalizedKey(pendingSaveItem.text)
                        if onSaveOption(pendingSaveItem, []) || isAlreadySaved(pendingSaveItem) {
                            locallySavedKeys.insert(key)
                        }
                        isCategoryPickerPresented = false
                        self.pendingSaveItem = nil
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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
                                pendingSaveItem = item
                                isCategoryPickerPresented = true
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

private struct NativeAlternativeCategoryPickerSheet: View {
    let item: NativeAlternativeItem
    let categories: [DictionaryCategory]
    let onCreateCategory: (String) -> DictionaryCategory?
    let onSave: ([UUID]) -> Void
    let onSaveWithoutCategory: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryIDs: Set<UUID> = []
    @State private var showAddAlert = false
    @State private var newCategoryName = ""
    @State private var categoryValidationErrorMessage = ""
    @State private var showCategoryValidationErrorAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SAVE TO MY DICTIONARY")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text(item.text)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORY")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)

                            if categories.isEmpty {
                                Text("카테고리가 아직 없습니다. 바로 저장하거나 새 카테고리를 만들어서 저장할 수 있어요.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemBackground))
                                    )
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(categories) { category in
                                        Button(action: {
                                            toggle(category.id)
                                        }) {
                                            HStack {
                                                Text(category.name)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Image(systemName: selectedCategoryIDs.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(selectedCategoryIDs.contains(category.id) ? Color.blue : .secondary)
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color(uiColor: .secondarySystemBackground))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                VStack(spacing: 10) {
                    Button(action: {
                        onSave(Array(selectedCategoryIDs))
                        dismiss()
                    }) {
                        Text(selectedCategoryIDs.isEmpty ? "Save to Dictionary" : "Save with Selected Categories")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Button(action: {
                            onSaveWithoutCategory()
                            dismiss()
                        }) {
                            Text("Save without Category")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            newCategoryName = ""
                            showAddAlert = true
                        }) {
                            Label("New", systemImage: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("새 카테고리", isPresented: $showAddAlert) {
                TextField("카테고리 이름", text: $newCategoryName)
                Button("추가") {
                    if let validationMessage = validateCategoryName(newCategoryName) {
                        categoryValidationErrorMessage = validationMessage
                        showCategoryValidationErrorAlert = true
                    } else if let created = onCreateCategory(newCategoryName) {
                        selectedCategoryIDs.insert(created.id)
                    } else {
                        categoryValidationErrorMessage = "카테고리를 저장하지 못했습니다. 다시 시도해주세요."
                        showCategoryValidationErrorAlert = true
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("저장할 새 카테고리 이름을 입력하세요.")
            }
            .alert("카테고리 저장 실패", isPresented: $showCategoryValidationErrorAlert) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(categoryValidationErrorMessage)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedCategoryIDs.contains(id) {
            selectedCategoryIDs.remove(id)
        } else {
            selectedCategoryIDs.insert(id)
        }
    }

    private func validateCategoryName(_ rawName: String) -> String? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "카테고리 이름을 입력하세요." }
        if categories.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return "같은 이름의 카테고리가 이미 있습니다."
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: SampleData.conversations[0])
            .environmentObject(ChatStore())
    }
}


private struct GrammarCorrectionCategoryPickerSheet: View {
    let correctedText: String
    let originalText: String
    let categories: [DictionaryCategory]
    let isAlreadySaved: Bool
    let onCreateCategory: (String) -> DictionaryCategory?
    let onSave: ([UUID]) -> Void
    let onSaveWithoutCategory: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryIDs: Set<UUID> = []
    @State private var showAddAlert = false
    @State private var newCategoryName = ""
    @State private var categoryValidationErrorMessage = ""
    @State private var showCategoryValidationErrorAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SAVE CORRECTED SENTENCE")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text(correctedText)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }

                        if !originalText.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ORIGINAL")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.5)
                                Text(originalText)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CATEGORIES")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .tracking(0.5)
                                Spacer()
                                Button("New") {
                                    newCategoryName = ""
                                    showAddAlert = true
                                }
                                .font(.system(size: 13, weight: .semibold))
                            }

                            if categories.isEmpty {
                                Text("No categories yet. You can save without a category, or create one.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemBackground))
                                    )
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(categories) { category in
                                        Button(action: {
                                            if selectedCategoryIDs.contains(category.id) {
                                                selectedCategoryIDs.remove(category.id)
                                            } else {
                                                selectedCategoryIDs.insert(category.id)
                                            }
                                        }) {
                                            HStack {
                                                Text(category.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Image(systemName: selectedCategoryIDs.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(selectedCategoryIDs.contains(category.id) ? Color.blue : .secondary)
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color(uiColor: .secondarySystemBackground))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                VStack(spacing: 10) {
                    Button(action: {
                        onSave(Array(selectedCategoryIDs))
                        dismiss()
                    }) {
                        Text(isAlreadySaved ? "Already Saved" : "Save")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isAlreadySaved ? Color.green : Color.blue)
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        onSaveWithoutCategory()
                        dismiss()
                    }) {
                        Text("Save without Category")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Save corrected sentence")
            .navigationBarTitleDisplayMode(.inline)
            .alert("New Category", isPresented: $showAddAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    if let category = onCreateCategory(newCategoryName) {
                        selectedCategoryIDs.insert(category.id)
                    } else {
                        categoryValidationErrorMessage = "Category name is empty or already exists."
                        showCategoryValidationErrorAlert = true
                    }
                }
            } message: {
                Text("Create a category for your dictionary.")
            }
            .alert("Category Error", isPresented: $showCategoryValidationErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(categoryValidationErrorMessage)
            }
        }
    }
}

import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject {
    private struct PersistedState: Codable {
        let conversations: [Conversation]
        let messagesByConversationID: [UUID: [ChatMessage]]
        let dictionaryEntries: [DictionaryEntry]
        let dictionaryCategories: [DictionaryCategory]
        let aiProfilesByConversationID: [UUID: AIProfileSettings]?
        let conversationMemoryByConversationID: [UUID: String]?
    }

    enum CategoryNameValidationError: LocalizedError {
        case empty
        case duplicate

        var errorDescription: String? {
            switch self {
            case .empty:
                return "카테고리 이름을 입력하세요."
            case .duplicate:
                return "같은 이름의 카테고리가 이미 있습니다."
            }
        }
    }

    private let persistenceKey = "geminichatbot.chatstore.v1"
    private let userDefaults: UserDefaults

    @Published private(set) var conversations: [Conversation]
    @Published private var messagesByConversationID: [UUID: [ChatMessage]] = [:]
    @Published private(set) var dictionaryEntries: [DictionaryEntry] = []
    @Published private(set) var dictionaryCategories: [DictionaryCategory] = []
    @Published private(set) var aiProfilesByConversationID: [UUID: AIProfileSettings] = [:]
    @Published private(set) var conversationMemoryByConversationID: [UUID: String] = [:]
    @Published var selectedDictionaryCategoryFilter: DictionaryCategoryFilter = .all

    init(conversations: [Conversation] = SampleData.conversations, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.conversations = conversations
        for conversation in conversations {
            messagesByConversationID[conversation.id] = SampleData.initialMessages(for: conversation.name)
            aiProfilesByConversationID[conversation.id] = AIProfileSettings(name: conversation.name)
        }
        loadPersistedState()
        ensureAIProfilesForConversations()
    }

    func messages(for conversation: Conversation) -> [ChatMessage] {
        messagesByConversationID[conversation.id] ?? []
    }

    func sendUserMessage(_ text: String, in conversation: Conversation) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appendMessage(ChatMessage(role: .user, text: trimmed, timeText: currentTimeText()), to: conversation)
        updateConversationPreview(for: conversation, lastMessage: trimmed, unreadCount: 0)
        persistState()
        let recentHistory = recentChatHistoryForBackend(in: conversation.id, excludingLatestUserMessage: true)
        let currentMemorySummary = conversationMemoryByConversationID[conversation.id] ?? ""

        Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await BackendAPIClient.shared.chatReply(
                    message: trimmed,
                    history: recentHistory,
                    memorySummary: currentMemorySummary
                )
                await MainActor.run {
                    self.appendMessage(ChatMessage(role: .ai, text: reply, timeText: self.currentTimeText()), to: conversation)
                    self.updateConversationPreview(for: conversation, lastMessage: reply, unreadCount: 0)
                    self.persistState()
                    self.refreshConversationMemorySummary(for: conversation.id)
                }
            } catch {
                await MainActor.run {
                    let fallback = "잠시 오류가 있었어요. 한 번만 더 말해줄래?"
                    self.appendMessage(ChatMessage(role: .ai, text: fallback, timeText: self.currentTimeText()), to: conversation)
                    self.updateConversationPreview(for: conversation, lastMessage: fallback, unreadCount: 0)
                    self.persistState()
                }
            }
        }
    }

    func markConversationOpened(_ conversation: Conversation) {
        updateConversationPreview(for: conversation, lastMessage: conversation.lastMessage, unreadCount: 0, keepMessage: true)
        persistState()
    }

    func conversationMemorySummary(for conversationID: UUID) -> String {
        conversationMemoryByConversationID[conversationID] ?? ""
    }

    func saveNativeAlternative(_ item: NativeAlternativeItem, originalText: String, categoryIDs: [UUID] = []) -> Bool {
        let normalizedTarget = normalizeDictionaryText(item.text)
        guard !normalizedTarget.isEmpty else { return false }
        if dictionaryEntries.contains(where: { normalizeDictionaryText($0.text) == normalizedTarget }) {
            return false
        }

        let entry = DictionaryEntry(
            kind: .native,
            text: item.text.trimmingCharacters(in: .whitespacesAndNewlines),
            originalText: originalText.trimmingCharacters(in: .whitespacesAndNewlines),
            tone: item.tone,
            nuance: item.nuance,
            categoryIDs: categoryIDs
        )
        dictionaryEntries.insert(entry, at: 0)
        persistState()
        return true
    }

    func isSavedDictionaryText(_ text: String) -> Bool {
        let normalizedTarget = normalizeDictionaryText(text)
        guard !normalizedTarget.isEmpty else { return false }
        return dictionaryEntries.contains(where: { normalizeDictionaryText($0.text) == normalizedTarget })
    }

    func filteredDictionaryEntries() -> [DictionaryEntry] {
        switch selectedDictionaryCategoryFilter {
        case .all:
            return dictionaryEntries
        case .uncategorized:
            return dictionaryEntries.filter { $0.categoryIDs.isEmpty }
        case .category(let categoryID):
            return dictionaryEntries.filter { $0.categoryIDs.contains(categoryID) }
        }
    }

    func categoryName(for id: UUID) -> String? {
        dictionaryCategories.first(where: { $0.id == id })?.name
    }

    func category(for id: UUID) -> DictionaryCategory? {
        dictionaryCategories.first(where: { $0.id == id })
    }

    func categoryBadges(for entry: DictionaryEntry) -> [String] {
        entry.categoryIDs.compactMap(categoryName(for:))
    }

    func createDictionaryCategory(named rawName: String) -> DictionaryCategory? {
        guard let name = validatedCategoryName(rawName, excluding: nil) else { return nil }
        let category = DictionaryCategory(name: name)
        dictionaryCategories.append(category)
        dictionaryCategories.sort { $0.createdAt < $1.createdAt }
        persistState()
        return category
    }

    func renameDictionaryCategory(id: UUID, to rawName: String) -> Bool {
        guard let name = validatedCategoryName(rawName, excluding: id) else { return false }
        guard let index = dictionaryCategories.firstIndex(where: { $0.id == id }) else { return false }
        let current = dictionaryCategories[index]
        dictionaryCategories[index] = DictionaryCategory(id: current.id, name: name, createdAt: current.createdAt)
        persistState()
        return true
    }

    func deleteDictionaryCategory(_ id: UUID) {
        dictionaryCategories.removeAll { $0.id == id }
        dictionaryEntries = dictionaryEntries.map { entry in
            let nextIDs = entry.categoryIDs.filter { $0 != id }
            guard nextIDs != entry.categoryIDs else { return entry }
            return DictionaryEntry(
                id: entry.id,
                kind: entry.kind,
                text: entry.text,
                originalText: entry.originalText,
                tone: entry.tone,
                nuance: entry.nuance,
                createdAt: entry.createdAt,
                categoryIDs: nextIDs
            )
        }
        if case .category(let selectedID) = selectedDictionaryCategoryFilter, selectedID == id {
            selectedDictionaryCategoryFilter = .all
        }
        persistState()
    }

    func setCategories(_ categoryIDs: [UUID], for entryID: UUID) {
        guard let index = dictionaryEntries.firstIndex(where: { $0.id == entryID }) else { return }
        let entry = dictionaryEntries[index]
        let validIDs = categoryIDs.filter { id in dictionaryCategories.contains(where: { $0.id == id }) }
        let uniqueIDs = Array(Set(validIDs))
        dictionaryEntries[index] = DictionaryEntry(
            id: entry.id,
            kind: entry.kind,
            text: entry.text,
            originalText: entry.originalText,
            tone: entry.tone,
            nuance: entry.nuance,
            createdAt: entry.createdAt,
            categoryIDs: uniqueIDs
        )
        persistState()
    }

    func deleteDictionaryEntry(_ entryID: UUID) {
        dictionaryEntries.removeAll { $0.id == entryID }
        persistState()
    }

    func setDictionaryCategoryFilter(_ filter: DictionaryCategoryFilter) {
        selectedDictionaryCategoryFilter = filter
    }

    func aiProfile(for conversation: Conversation) -> AIProfileSettings {
        aiProfile(for: conversation.id, fallbackName: conversation.name)
    }

    func aiProfile(for conversationID: UUID, fallbackName: String = "AI") -> AIProfileSettings {
        aiProfilesByConversationID[conversationID] ?? AIProfileSettings(name: fallbackName)
    }

    func updateAIProfile(
        for conversationID: UUID,
        name rawName: String,
        avatarImageData: Data?,
        voicePreset: String
    ) {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty ? (conversations.first(where: { $0.id == conversationID })?.name ?? "AI") : trimmedName
        let safeVoice = AIProfileSettings.supportedVoicePresets.contains(voicePreset) ? voicePreset : "Kore"

        aiProfilesByConversationID[conversationID] = AIProfileSettings(
            name: safeName,
            avatarImageData: avatarImageData,
            voicePreset: safeVoice
        )

        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            let current = conversations[index]
            conversations[index] = Conversation(
                id: current.id,
                name: safeName,
                lastMessage: current.lastMessage,
                timeText: current.timeText,
                unreadCount: current.unreadCount,
                avatarText: avatarInitial(from: safeName)
            )
        }
        persistState()
    }

    func clearConversationHistory(for conversationID: UUID) {
        messagesByConversationID[conversationID] = []

        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            let current = conversations[index]
            conversations[index] = Conversation(
                id: current.id,
                name: current.name,
                lastMessage: "",
                timeText: "",
                unreadCount: 0,
                avatarText: current.avatarText
            )
        }

        persistState()
    }

    func selectedDictionaryCategoryTitle() -> String? {
        switch selectedDictionaryCategoryFilter {
        case .all:
            return nil
        case .uncategorized:
            return "미분류"
        case .category(let id):
            return categoryName(for: id)
        }
    }

    func dictionaryEntryCount(for filter: DictionaryCategoryFilter) -> Int {
        switch filter {
        case .all:
            return dictionaryEntries.count
        case .uncategorized:
            return dictionaryEntries.filter { $0.categoryIDs.isEmpty }.count
        case .category(let id):
            return dictionaryEntries.filter { $0.categoryIDs.contains(id) }.count
        }
    }

    func validateDictionaryCategoryName(_ rawName: String, excluding id: UUID? = nil) -> CategoryNameValidationError? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if dictionaryCategories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return .duplicate
        }
        return nil
    }

    private func appendMessage(_ message: ChatMessage, to conversation: Conversation) {
        var list = messagesByConversationID[conversation.id] ?? []
        list.append(message)
        messagesByConversationID[conversation.id] = list
    }

    private func updateConversationPreview(for conversation: Conversation, lastMessage: String, unreadCount: Int, keepMessage: Bool = false) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        let current = conversations[index]
        let latestTime = keepMessage ? current.timeText : currentTimeText()
        conversations[index] = Conversation(
            id: current.id,
            name: current.name,
            lastMessage: keepMessage ? current.lastMessage : lastMessage,
            timeText: latestTime,
            unreadCount: unreadCount,
            avatarText: current.avatarText
        )
    }

    private func avatarInitial(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "A" }
        return String(first).uppercased()
    }

    private func currentTimeText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func normalizeDictionaryText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.!?]+$", with: "", options: .regularExpression)
            .lowercased()
    }

    private func recentChatHistoryForBackend(
        in conversationID: UUID,
        excludingLatestUserMessage: Bool,
        limit: Int = 12
    ) -> [BackendChatHistoryItem] {
        var messages = messagesByConversationID[conversationID] ?? []
        if excludingLatestUserMessage,
           let last = messages.last,
           last.role == .user {
            messages.removeLast()
        }

        return messages
            .suffix(limit)
            .compactMap { message in
                let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return BackendChatHistoryItem(
                    role: message.role == .user ? "user" : "ai",
                    text: trimmed
                )
            }
    }

    private func refreshConversationMemorySummary(for conversationID: UUID) {
        let history = recentChatHistoryForBackend(
            in: conversationID,
            excludingLatestUserMessage: false,
            limit: 20
        )
        guard !history.isEmpty else { return }

        let currentSummary = conversationMemoryByConversationID[conversationID] ?? ""
        Task { [weak self] in
            guard let self else { return }
            do {
                let updated = try await BackendAPIClient.shared.updateMemorySummary(
                    currentSummary: currentSummary,
                    history: history
                )
                await MainActor.run {
                    let normalized = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard normalized != currentSummary else { return }
                    if normalized.isEmpty {
                        self.conversationMemoryByConversationID.removeValue(forKey: conversationID)
                    } else {
                        self.conversationMemoryByConversationID[conversationID] = normalized
                    }
                    self.persistState()
                }
            } catch {
                // Memory update failures should not interrupt the main chat flow.
            }
        }
    }

    private func validatedCategoryName(_ rawName: String, excluding id: UUID?) -> String? {
        if validateDictionaryCategoryName(rawName, excluding: id) != nil {
            return nil
        }
        return rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadPersistedState() {
        guard let data = userDefaults.data(forKey: persistenceKey) else { return }
        do {
            let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
            conversations = decoded.conversations
            messagesByConversationID = decoded.messagesByConversationID
            dictionaryEntries = decoded.dictionaryEntries
            dictionaryCategories = decoded.dictionaryCategories
            aiProfilesByConversationID = decoded.aiProfilesByConversationID ?? [:]
            conversationMemoryByConversationID = decoded.conversationMemoryByConversationID ?? [:]
        } catch {
            print("ChatStore persistence load failed:", error)
        }
    }

    private func persistState() {
        let snapshot = PersistedState(
            conversations: conversations,
            messagesByConversationID: messagesByConversationID,
            dictionaryEntries: dictionaryEntries,
            dictionaryCategories: dictionaryCategories,
            aiProfilesByConversationID: aiProfilesByConversationID
            ,
            conversationMemoryByConversationID: conversationMemoryByConversationID
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            userDefaults.set(data, forKey: persistenceKey)
        } catch {
            print("ChatStore persistence save failed:", error)
        }
    }

    private func ensureAIProfilesForConversations() {
        var changed = false
        for conversation in conversations {
            if aiProfilesByConversationID[conversation.id] == nil {
                aiProfilesByConversationID[conversation.id] = AIProfileSettings(name: conversation.name)
                changed = true
            }
        }
        if changed {
            persistState()
        }
    }
}

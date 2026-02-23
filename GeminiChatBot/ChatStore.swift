import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published private var messagesByConversationID: [UUID: [ChatMessage]] = [:]
    @Published private(set) var dictionaryEntries: [DictionaryEntry] = []
    @Published private(set) var dictionaryCategories: [DictionaryCategory] = []
    @Published var selectedDictionaryCategoryFilter: DictionaryCategoryFilter = .all

    init(conversations: [Conversation] = SampleData.conversations) {
        self.conversations = conversations
        for conversation in conversations {
            messagesByConversationID[conversation.id] = SampleData.initialMessages(for: conversation.name)
        }
    }

    func messages(for conversation: Conversation) -> [ChatMessage] {
        messagesByConversationID[conversation.id] ?? []
    }

    func sendUserMessage(_ text: String, in conversation: Conversation) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appendMessage(ChatMessage(role: .user, text: trimmed, timeText: currentTimeText()), to: conversation)
        updateConversationPreview(for: conversation, lastMessage: trimmed, unreadCount: 0)

        let reply = "Got it. That sounds good. Can you tell me a little more?"
        appendMessage(ChatMessage(role: .ai, text: reply, timeText: currentTimeText()), to: conversation)
        updateConversationPreview(for: conversation, lastMessage: reply, unreadCount: 0)
    }

    func markConversationOpened(_ conversation: Conversation) {
        updateConversationPreview(for: conversation, lastMessage: conversation.lastMessage, unreadCount: 0, keepMessage: true)
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

    func categoryBadges(for entry: DictionaryEntry) -> [String] {
        entry.categoryIDs.compactMap(categoryName(for:))
    }

    func createDictionaryCategory(named rawName: String) -> DictionaryCategory? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard !dictionaryCategories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        let category = DictionaryCategory(name: name)
        dictionaryCategories.append(category)
        dictionaryCategories.sort { $0.createdAt < $1.createdAt }
        return category
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
    }

    func deleteDictionaryEntry(_ entryID: UUID) {
        dictionaryEntries.removeAll { $0.id == entryID }
    }

    func setDictionaryCategoryFilter(_ filter: DictionaryCategoryFilter) {
        selectedDictionaryCategoryFilter = filter
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
}

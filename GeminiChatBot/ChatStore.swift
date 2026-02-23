import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [Conversation]
    @Published private var messagesByConversationID: [UUID: [ChatMessage]] = [:]

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
}

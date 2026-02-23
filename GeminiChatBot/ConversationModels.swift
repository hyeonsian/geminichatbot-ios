import Foundation

struct Conversation: Identifiable, Hashable {
    let id: UUID
    let name: String
    let lastMessage: String
    let timeText: String
    let unreadCount: Int
    let avatarText: String

    init(
        id: UUID = UUID(),
        name: String,
        lastMessage: String,
        timeText: String,
        unreadCount: Int,
        avatarText: String
    ) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.timeText = timeText
        self.unreadCount = unreadCount
        self.avatarText = avatarText
    }
}

struct ChatMessage: Identifiable, Hashable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let timeText: String

    enum ChatRole: Hashable {
        case user
        case ai
    }
}

enum SampleData {
    static let conversations: [Conversation] = [
        Conversation(
            name: "Cat",
            lastMessage: "Hey there! I was wondering when you'd show up.",
            timeText: "13:27",
            unreadCount: 2,
            avatarText: "C"
        ),
        Conversation(
            name: "English Coach",
            lastMessage: "Try saying it a little more naturally.",
            timeText: "12:41",
            unreadCount: 0,
            avatarText: "E"
        ),
        Conversation(
            name: "Practice Buddy",
            lastMessage: "What did you do today?",
            timeText: "11:18",
            unreadCount: 1,
            avatarText: "P"
        )
    ]

    static func initialMessages(for name: String) -> [ChatMessage] {
        [
            ChatMessage(role: .ai, text: "Hey! I'm \(name). What do you want to practice today?", timeText: "17:06"),
            ChatMessage(role: .user, text: "I want to improve my English speaking.", timeText: "17:06"),
            ChatMessage(role: .ai, text: "Nice. Tell me about your day in English.", timeText: "17:06")
        ]
    }
}

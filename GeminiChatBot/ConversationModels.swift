import Foundation

struct Conversation: Identifiable, Hashable, Codable {
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

struct ChatMessage: Identifiable, Hashable, Codable {
    let id: UUID
    let role: ChatRole
    let text: String
    let timeText: String

    enum ChatRole: String, Hashable, Codable {
        case user
        case ai
    }

    init(id: UUID = UUID(), role: ChatRole, text: String, timeText: String) {
        self.id = id
        self.role = role
        self.text = text
        self.timeText = timeText
    }
}

struct DictionaryEntry: Identifiable, Hashable, Codable {
    struct GrammarCorrectionPair: Hashable, Codable {
        let wrong: String
        let right: String
        let reason: String?

        init(wrong: String, right: String, reason: String? = nil) {
            self.wrong = wrong
            self.right = right
            self.reason = reason
        }
    }

    let id: UUID
    let kind: EntryKind
    let text: String
    let originalText: String
    let tone: String
    let nuance: String
    let createdAt: Date
    let categoryIDs: [UUID]
    let grammarCorrections: [GrammarCorrectionPair]?

    enum EntryKind: String, Hashable, Codable {
        case native
        case grammar

        var label: String {
            switch self {
            case .native: return "#Native Expression"
            case .grammar: return "#Grammar Correction"
            }
        }
    }

    init(
        id: UUID = UUID(),
        kind: EntryKind,
        text: String,
        originalText: String,
        tone: String,
        nuance: String,
        createdAt: Date = Date(),
        categoryIDs: [UUID] = [],
        grammarCorrections: [GrammarCorrectionPair]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.originalText = originalText
        self.tone = tone
        self.nuance = nuance
        self.createdAt = createdAt
        self.categoryIDs = categoryIDs
        self.grammarCorrections = grammarCorrections
    }
}

struct DictionaryCategory: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct AIProfileSettings: Hashable, Codable {
    struct PersonaProfile: Hashable, Codable {
        var warmth: Int
        var playfulness: Int
        var directness: Int
        var curiosity: Int
        var verbosity: Int

        init(
            warmth: Int = 4,
            playfulness: Int = 3,
            directness: Int = 3,
            curiosity: Int = 4,
            verbosity: Int = 2
        ) {
            self.warmth = Self.clamp(warmth)
            self.playfulness = Self.clamp(playfulness)
            self.directness = Self.clamp(directness)
            self.curiosity = Self.clamp(curiosity)
            self.verbosity = Self.clamp(verbosity)
        }

        private static func clamp(_ value: Int) -> Int {
            min(5, max(1, value))
        }

        static let `default` = PersonaProfile()
    }

    enum KoreanTranslationSpeechLevel: String, Hashable, Codable, CaseIterable {
        case polite
        case casual

        var displayName: String {
            switch self {
            case .polite: return "존댓말"
            case .casual: return "반말"
            }
        }
    }

    var name: String
    var avatarImageData: Data?
    var voicePreset: String
    var koreanTranslationSpeechLevel: KoreanTranslationSpeechLevel
    var personaProfile: PersonaProfile

    init(
        name: String,
        avatarImageData: Data? = nil,
        voicePreset: String = "Kore",
        koreanTranslationSpeechLevel: KoreanTranslationSpeechLevel = .polite,
        personaProfile: PersonaProfile = .default
    ) {
        self.name = name
        self.avatarImageData = avatarImageData
        self.voicePreset = voicePreset
        self.koreanTranslationSpeechLevel = koreanTranslationSpeechLevel
        self.personaProfile = personaProfile
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case avatarImageData
        case voicePreset
        case koreanTranslationSpeechLevel
        case personaProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        voicePreset = try container.decodeIfPresent(String.self, forKey: .voicePreset) ?? "Kore"
        koreanTranslationSpeechLevel = try container.decodeIfPresent(KoreanTranslationSpeechLevel.self, forKey: .koreanTranslationSpeechLevel) ?? .polite
        personaProfile = try container.decodeIfPresent(PersonaProfile.self, forKey: .personaProfile) ?? .default
    }

    static let supportedVoicePresets: [String] = [
        "Kore",
        "Puck",
        "Achird",
        "Aoede",
        "Charon",
        "Fenrir"
    ]
}

struct ConversationMemoryProfile: Hashable, Codable {
    var hobbies: [String]
    var goals: [String]
    var projects: [String]
    var personalityTraits: [String]
    var dailyRoutine: [String]
    var preferences: [String]
    var background: [String]
    var notes: [String]

    init(
        hobbies: [String] = [],
        goals: [String] = [],
        projects: [String] = [],
        personalityTraits: [String] = [],
        dailyRoutine: [String] = [],
        preferences: [String] = [],
        background: [String] = [],
        notes: [String] = []
    ) {
        self.hobbies = hobbies
        self.goals = goals
        self.projects = projects
        self.personalityTraits = personalityTraits
        self.dailyRoutine = dailyRoutine
        self.preferences = preferences
        self.background = background
        self.notes = notes
    }

    static let empty = ConversationMemoryProfile()

    var isEmpty: Bool {
        hobbies.isEmpty &&
        goals.isEmpty &&
        projects.isEmpty &&
        personalityTraits.isEmpty &&
        dailyRoutine.isEmpty &&
        preferences.isEmpty &&
        background.isEmpty &&
        notes.isEmpty
    }

    func promptSummary(maxChars: Int = 2600) -> String {
        let sections: [(String, [String])] = [
            ("Hobbies", hobbies),
            ("Goals", goals),
            ("Projects", projects),
            ("Personality", personalityTraits),
            ("Daily Routine", dailyRoutine),
            ("Preferences", preferences),
            ("Background", background),
            ("Notes", notes)
        ]

        let text = sections
            .filter { !$0.1.isEmpty }
            .map { title, values in
                let bullets = values.map { "- \($0)" }.joined(separator: "\n")
                return "\(title):\n\(bullets)"
            }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars))
    }

    func debugSections() -> [(title: String, items: [String])] {
        [
            ("Hobbies", hobbies),
            ("Goals", goals),
            ("Projects", projects),
            ("Personality", personalityTraits),
            ("Daily Routine", dailyRoutine),
            ("Preferences", preferences),
            ("Background", background),
            ("Notes", notes)
        ].filter { !$0.items.isEmpty }
    }
}

enum DictionaryCategoryFilter: Hashable {
    case all
    case category(UUID)
    case uncategorized
}

enum SampleData {
    static let conversations: [Conversation] = [
        Conversation(
            id: UUID(uuidString: "E6A5E58E-908B-4C69-A53B-3B1A8AC6C001")!,
            name: "Cat",
            lastMessage: "Hey there! I was wondering when you'd show up.",
            timeText: "13:27",
            unreadCount: 2,
            avatarText: "C"
        ),
        Conversation(
            id: UUID(uuidString: "E6A5E58E-908B-4C69-A53B-3B1A8AC6C002")!,
            name: "English Coach",
            lastMessage: "Try saying it a little more naturally.",
            timeText: "12:41",
            unreadCount: 0,
            avatarText: "E"
        ),
        Conversation(
            id: UUID(uuidString: "E6A5E58E-908B-4C69-A53B-3B1A8AC6C003")!,
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

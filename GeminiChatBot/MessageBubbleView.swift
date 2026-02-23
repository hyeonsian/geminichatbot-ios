import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: ChatMessage
    var isSelected: Bool = false
    var highlightQuery: String = ""
    var isSearchMatched: Bool = false
    var isActiveSearchMatch: Bool = false

    var body: some View {
        HStack {
            if message.role == .ai {
                bubble
                    .frame(maxWidth: 290, alignment: .leading)
                Spacer(minLength: 34)
            } else {
                Spacer(minLength: 34)
                bubble
                    .frame(maxWidth: 290, alignment: .trailing)
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: message.role == .ai ? .leading : .trailing, spacing: 6) {
            messageTextView

            Text(message.timeText)
                .font(.system(size: 11))
                .foregroundStyle(message.role == .ai ? Color.secondary : Color.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(message.role == .ai ? Color(uiColor: .systemGray5) : Color.blue)
        )
        .overlay {
            if isSelected && message.role == .user {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
            } else if isActiveSearchMatch {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.orange.opacity(0.85), lineWidth: 2)
            } else if isSearchMatched {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.orange.opacity(0.28), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var messageTextView: some View {
        if let attributed = highlightedAttributedString(for: message.text, query: highlightQuery, isUserBubble: message.role == .user) {
            Text(attributed)
                .font(.system(size: 18))
                .multilineTextAlignment(message.role == .ai ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(message.text)
                .font(.system(size: 18))
                .foregroundStyle(message.role == .ai ? Color.primary : Color.white)
                .multilineTextAlignment(message.role == .ai ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func highlightedAttributedString(for source: String, query: String, isUserBubble: Bool) -> AttributedString? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        let nsSource = source as NSString
        let escaped = NSRegularExpression.escapedPattern(for: trimmedQuery)
        guard let regex = try? NSRegularExpression(pattern: escaped, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: source, options: [], range: NSRange(location: 0, length: nsSource.length))
        guard !matches.isEmpty else { return nil }

        var attributed = AttributedString(source)
        attributed.foregroundColor = isUserBubble ? .white : .primary

        for match in matches {
            guard let range = Range(match.range, in: source),
                  let attrRange = Range<AttributedString.Index>(range, in: attributed) else { continue }
            attributed[attrRange].backgroundColor = isUserBubble
                ? UIColor.white.withAlphaComponent(0.22)
                : UIColor.systemYellow.withAlphaComponent(0.45)
            attributed[attrRange].foregroundColor = isUserBubble ? .white : .primary
        }

        return attributed
    }
}

#Preview {
    VStack(spacing: 10) {
        MessageBubbleView(message: .init(role: .ai, text: "Hello, how are you doing today?", timeText: "17:06"))
        MessageBubbleView(message: .init(role: .user, text: "I'm good! I want to practice English.", timeText: "17:06"), isSelected: true)
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

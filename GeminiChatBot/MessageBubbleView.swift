import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: ChatMessage
    var isSelected: Bool = false

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
            Text(message.text)
                .font(.system(size: 18))
                .foregroundStyle(message.role == .ai ? Color.primary : Color.white)
                .multilineTextAlignment(message.role == .ai ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)

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
            }
        }
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

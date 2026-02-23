import SwiftUI
import UIKit

struct MessageBubbleView: View {
    let message: ChatMessage
    var isSelected: Bool = false
    var highlightQuery: String = ""
    var isSearchMatched: Bool = false
    var isActiveSearchMatch: Bool = false
    var translatedText: String? = nil
    var translationError: String? = nil
    var isTranslationLoading: Bool = false
    var onTapTranslate: (() -> Void)? = nil
    var onTapSpeak: (() -> Void)? = nil
    var isSpeechLoading: Bool = false
    var isSpeaking: Bool = false
    @State private var aiPrimaryTextWidth: CGFloat = 0

    private let bubbleContentMaxWidth: CGFloat = 262

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

            if message.role == .ai {
                aiTranslationContent
            }

            footerRow
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
    private var footerRow: some View {
        if message.role == .ai {
            HStack(alignment: .center, spacing: 6) {
                Spacer(minLength: 0)
                timeText
                if hasAIActionButtons {
                    aiActionButtons
                }
            }
        } else {
            HStack {
                Spacer(minLength: 0)
                timeText
            }
        }
    }

    private var timeText: some View {
        Text(message.timeText)
            .font(.system(size: 11))
            .foregroundStyle(message.role == .ai ? Color.secondary : Color.white.opacity(0.85))
    }

    @ViewBuilder
    private var aiTranslationContent: some View {
        if isTranslationLoading {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("번역 중...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: translationContentWidth, alignment: .leading)
            .padding(.top, 2)
            .transition(.opacity)
        } else if let translationError, !translationError.isEmpty {
            Text("번역 오류")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: translationContentWidth, alignment: .leading)
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if let translatedText, !translatedText.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider()
                    .overlay(Color.gray.opacity(0.25))
                Text(translatedText)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: translationContentWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: translationContentWidth, alignment: .leading)
            .padding(.top, 2)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func translateButton(action: @escaping () -> Void) -> some View {
        actionCircleButton(
            tint: translateButtonTint,
            isLoading: isTranslationLoading,
            systemImage: "globe",
            action: action
        )
    }

    private var translateButtonTint: Color {
        if translationError != nil { return .red }
        if translatedText != nil { return .green }
        return .blue
    }

    private var hasAIActionButtons: Bool {
        onTapTranslate != nil || onTapSpeak != nil
    }

    @ViewBuilder
    private var aiActionButtons: some View {
        HStack(spacing: 8) {
            if let onTapTranslate {
                translateButton(action: onTapTranslate)
            }
            if let onTapSpeak {
                speechButton(action: onTapSpeak)
            }
        }
    }

    private func speechButton(action: @escaping () -> Void) -> some View {
        actionCircleButton(
            tint: isSpeaking ? .green : .blue,
            isLoading: isSpeechLoading,
            systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
            action: action
        )
    }

    private func actionCircleButton(
        tint: Color,
        isLoading: Bool,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
            .background(
                Circle()
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                Circle()
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var translationContentWidth: CGFloat {
        let measured = max(aiPrimaryTextWidth, 0)
        if measured > 0 {
            return min(measured, bubbleContentMaxWidth)
        }
        return bubbleContentMaxWidth
    }

    @ViewBuilder
    private var messageTextView: some View {
        if let attributed = highlightedAttributedString(for: message.text, query: highlightQuery, isUserBubble: message.role == .user) {
            Text(attributed)
                .font(.system(size: 18))
                .multilineTextAlignment(message.role == .ai ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .background(primaryTextWidthReader)
        } else {
            Text(message.text)
                .font(.system(size: 18))
                .foregroundStyle(message.role == .ai ? Color.primary : Color.white)
                .multilineTextAlignment(message.role == .ai ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .background(primaryTextWidthReader)
        }
    }

    @ViewBuilder
    private var primaryTextWidthReader: some View {
        if message.role == .ai {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        let width = proxy.size.width
                        if width > 0 { aiPrimaryTextWidth = width }
                    }
                    .onChange(of: proxy.size.width) { width in
                        if width > 0 { aiPrimaryTextWidth = width }
                    }
            }
        } else {
            Color.clear
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

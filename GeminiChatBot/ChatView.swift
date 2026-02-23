import SwiftUI
import UIKit

struct ChatView: View {
    let conversation: Conversation

    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(chatStore.messages(for: conversation)) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 90)
                    }
                    .onAppear {
                        chatStore.markConversationOpened(conversation)
                        scrollToBottom(proxy)
                    }
                    .onChange(of: chatStore.messages(for: conversation).map(\ .id)) { _ in
                        scrollToBottom(proxy)
                    }
                }
            }

            inputBar
        }
        .toolbar(.hidden, for: .navigationBar)
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

            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.blue)
                    .frame(width: 28, height: 28)
            }
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = chatStore.messages(for: conversation).last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(conversation: SampleData.conversations[0])
            .environmentObject(ChatStore())
    }
}

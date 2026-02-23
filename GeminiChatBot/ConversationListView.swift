import SwiftUI
import UIKit

struct ConversationListView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @State private var isDictionaryPresented = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(chatStore.conversations) { conversation in
                                NavigationLink {
                                    ChatView(conversation: conversation)
                                        .environmentObject(chatStore)
                                } label: {
                                    ConversationRow(
                                        conversation: conversation,
                                        aiProfile: chatStore.aiProfile(for: conversation)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 100)
                    }
                }

                bottomBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isDictionaryPresented) {
                DictionaryView()
                    .environmentObject(chatStore)
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: {}) {
                Text("편집")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(Capsule())
            }

            Spacer()

            Text("메시지")
                .font(.system(size: 22, weight: .bold))

            Spacer()

            Button(action: {}) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: {}) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
            }

            Text("검색")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: {
                isDictionaryPresented = true
            }) {
                Image(systemName: "book")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
            }

            Button(action: {}) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.95))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let aiProfile: AIProfileSettings

    var body: some View {
        HStack(spacing: 12) {
            conversationAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(conversation.lastMessage)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text(conversation.timeText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 6)
                        .background(Color.blue)
                        .clipShape(Capsule())
                } else {
                    Color.clear.frame(width: 22, height: 22)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    @ViewBuilder
    private var conversationAvatar: some View {
        if let data = aiProfile.avatarImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
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
                    .frame(width: 54, height: 54)

                Text(conversation.avatarText)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(ChatStore())
}

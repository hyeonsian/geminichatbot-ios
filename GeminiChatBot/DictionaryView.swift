import SwiftUI
import UIKit

struct DictionaryView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if chatStore.dictionaryEntries.isEmpty {
                    ContentUnavailableView(
                        "내 사전이 비어 있어요",
                        systemImage: "book.closed",
                        description: Text("Native alternatives에서 저장한 표현이 여기에 쌓입니다.")
                    )
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatStore.dictionaryEntries) { entry in
                                DictionaryEntryCard(entry: entry)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("내 사전")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.blue)
                    }
                }
            }
        }
    }
}

private struct DictionaryEntryCard: View {
    let entry: DictionaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(entry.kind.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.kind == .native ? Color.blue : Color.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(entry.kind == .native ? Color.blue.opacity(0.12) : Color.orange.opacity(0.14))
                    )

                Spacer()

                Text(Self.timestampFormatter.string(from: entry.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !entry.originalText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("원래 메시지")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(entry.originalText)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.tone.isEmpty || !entry.nuance.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !entry.tone.isEmpty {
                        Text(entry.tone)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.blue)
                    }
                    if !entry.nuance.isEmpty {
                        Text(entry.nuance)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy/MM/dd HH:mm"
        return formatter
    }()
}

#Preview {
    DictionaryView()
        .environmentObject(ChatStore())
}

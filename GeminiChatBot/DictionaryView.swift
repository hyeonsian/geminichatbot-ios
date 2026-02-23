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

                if chatStore.filteredDictionaryEntries().isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatStore.filteredDictionaryEntries()) { entry in
                                DictionaryEntryCard(
                                    entry: entry,
                                    categoryNames: chatStore.categoryBadges(for: entry)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(Color.blue)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 4) {
                        Text("내 사전")
                            .font(.system(size: 17, weight: .bold))
                        if let subtitle = chatStore.selectedDictionaryCategoryTitle() {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DictionaryCategoriesView()
                            .environmentObject(chatStore)
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.blue)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        let description: String
        switch chatStore.selectedDictionaryCategoryFilter {
        case .all:
            description = "Native alternatives에서 저장한 표현이 여기에 쌓입니다."
        case .uncategorized:
            description = "카테고리에 분류되지 않은 항목이 없습니다."
        case .category:
            description = "이 카테고리에 저장된 항목이 없습니다."
        }

        ContentUnavailableView(
            "내 사전이 비어 있어요",
            systemImage: "book.closed",
            description: Text(description)
        )
        .padding(.horizontal, 24)
    }
}

private struct DictionaryEntryCard: View {
    let entry: DictionaryEntry
    let categoryNames: [String]

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

            if !categoryNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(categoryNames.prefix(2)), id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                    }
                    if categoryNames.count > 2 {
                        Text("+\(categoryNames.count - 2)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
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
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.blue.opacity(0.08), lineWidth: 1)
        )
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy/MM/dd HH:mm"
        return formatter
    }()
}

private struct DictionaryCategoriesView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAddAlert = false
    @State private var newCategoryName = ""

    var body: some View {
        List {
            Section {
                categoryRow(title: "전체", isSelected: isSelected(.all)) {
                    chatStore.setDictionaryCategoryFilter(.all)
                    dismiss()
                }
                categoryRow(title: "미분류", isSelected: isSelected(.uncategorized)) {
                    chatStore.setDictionaryCategoryFilter(.uncategorized)
                    dismiss()
                }
            }

            if !chatStore.dictionaryCategories.isEmpty {
                Section("카테고리") {
                    ForEach(chatStore.dictionaryCategories) { category in
                        categoryRow(
                            title: category.name,
                            isSelected: isSelected(.category(category.id))
                        ) {
                            chatStore.setDictionaryCategoryFilter(.category(category.id))
                            dismiss()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("카테고리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    newCategoryName = ""
                    showAddAlert = true
                }) {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.blue)
                }
            }
        }
        .alert("새 카테고리", isPresented: $showAddAlert) {
            TextField("카테고리 이름", text: $newCategoryName)
            Button("추가") {
                _ = chatStore.createDictionaryCategory(named: newCategoryName)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("사전 분류용 카테고리 이름을 입력하세요.")
        }
    }

    private func isSelected(_ filter: DictionaryCategoryFilter) -> Bool {
        chatStore.selectedDictionaryCategoryFilter == filter
    }

    private func categoryRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DictionaryView()
        .environmentObject(ChatStore())
}

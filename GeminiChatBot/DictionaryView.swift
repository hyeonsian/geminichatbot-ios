import SwiftUI
import UIKit

struct DictionaryView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var categoryEditEntry: DictionaryEntry?
    @State private var navigationPath: [DictionaryRoute] = []
    @State private var showCategoryManageDialog = false
    @State private var showRenameCategoryAlert = false
    @State private var renameCategoryName = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if filteredEntries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                            DictionaryEntryCard(
                                entry: entry,
                                categoryNames: chatStore.categoryBadges(for: entry),
                                leadingTopCaption: index == 0 ? firstCardTopCaption : nil
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    categoryEditEntry = entry
                                } label: {
                                    Label("Category", systemImage: "plus")
                                }
                                .tint(Color(red: 0.73, green: 0.86, blue: 0.98))

                                Button(role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        chatStore.deleteDictionaryEntry(entry.id)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "minus")
                                }
                                .tint(Color(red: 0.98, green: 0.78, blue: 0.80))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: handleBackButtonTap) {
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
                    Button(action: handleTopRightCategoryButtonTap) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.blue)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: DictionaryRoute.self) { route in
                switch route {
                case .categories:
                    DictionaryCategoriesView()
                        .environmentObject(chatStore)
                }
            }
        }
        .sheet(item: $categoryEditEntry) { entry in
            DictionaryEntryCategoryEditorSheet(
                entry: entry,
                categories: chatStore.dictionaryCategories,
                onCreateCategory: { name in
                    chatStore.createDictionaryCategory(named: name)
                },
                onSave: { selectedCategoryIDs in
                    chatStore.setCategories(selectedCategoryIDs, for: entry.id)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "카테고리 관리",
            isPresented: $showCategoryManageDialog,
            titleVisibility: .visible
        ) {
            if selectedManagedCategory != nil {
                Button("카테고리 이름 변경") {
                    renameCategoryName = selectedManagedCategory?.name ?? ""
                    showRenameCategoryAlert = true
                }
                Button("카테고리 삭제", role: .destructive) {
                    if let category = selectedManagedCategory {
                        chatStore.deleteDictionaryCategory(category.id)
                    }
                }
                Button("카테고리 선택 페이지 열기") {
                    openCategoriesPage()
                }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("카테고리 이름 변경", isPresented: $showRenameCategoryAlert) {
            TextField("카테고리 이름", text: $renameCategoryName)
            Button("저장") {
                if let category = selectedManagedCategory {
                    _ = chatStore.renameDictionaryCategory(id: category.id, to: renameCategoryName)
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("새 카테고리 이름을 입력하세요.")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "내 사전이 비어 있어요",
            systemImage: "book.closed",
            description: Text(emptyStateDescription)
        )
        .padding(.horizontal, 24)
    }

    private var emptyStateDescription: String {
        switch chatStore.selectedDictionaryCategoryFilter {
        case .all:
            return "Native alternatives에서 저장한 표현이 여기에 쌓입니다."
        case .uncategorized:
            return "카테고리에 분류되지 않은 항목이 없습니다."
        case .category:
            return "이 카테고리에 저장된 항목이 없습니다."
        }
    }

    private var filteredEntries: [DictionaryEntry] {
        chatStore.filteredDictionaryEntries()
    }

    private var selectedManagedCategory: DictionaryCategory? {
        guard case .category(let id) = chatStore.selectedDictionaryCategoryFilter else { return nil }
        return chatStore.category(for: id)
    }

    private var firstCardTopCaption: String? {
        guard case .category = chatStore.selectedDictionaryCategoryFilter else { return nil }
        let count = filteredEntries.count
        return count == 1 ? "1 item" : "\(count) items"
    }

    private func handleBackButtonTap() {
        switch chatStore.selectedDictionaryCategoryFilter {
        case .category:
            openCategoriesPage()
        default:
            dismiss()
        }
    }

    private func handleTopRightCategoryButtonTap() {
        if selectedManagedCategory != nil {
            showCategoryManageDialog = true
        } else {
            openCategoriesPage()
        }
    }

    private func openCategoriesPage() {
        guard navigationPath.last != .categories else { return }
        navigationPath.append(.categories)
    }
}

private enum DictionaryRoute: Hashable {
    case categories
}

private struct DictionaryEntryCategoryEditorSheet: View {
    let entry: DictionaryEntry
    let categories: [DictionaryCategory]
    let onCreateCategory: (String) -> DictionaryCategory?
    let onSave: ([UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategoryIDs: Set<UUID>
    @State private var showAddAlert = false
    @State private var newCategoryName = ""

    init(
        entry: DictionaryEntry,
        categories: [DictionaryCategory],
        onCreateCategory: @escaping (String) -> DictionaryCategory?,
        onSave: @escaping ([UUID]) -> Void
    ) {
        self.entry = entry
        self.categories = categories
        self.onCreateCategory = onCreateCategory
        self.onSave = onSave
        _selectedCategoryIDs = State(initialValue: Set(entry.categoryIDs))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EXPRESSION")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)
                            Text(entry.text)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CATEGORIES")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                                .tracking(0.5)

                            if categories.isEmpty {
                                Text("카테고리가 없습니다. 새 카테고리를 만든 뒤 분류할 수 있어요.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemBackground))
                                    )
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(categories) { category in
                                        Button(action: {
                                            toggle(category.id)
                                        }) {
                                            HStack {
                                                Text(category.name)
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                                Image(systemName: selectedCategoryIDs.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(selectedCategoryIDs.contains(category.id) ? Color.blue : .secondary)
                                            }
                                            .padding(12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color(uiColor: .secondarySystemBackground))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }

                VStack(spacing: 10) {
                    Button(action: {
                        onSave(Array(selectedCategoryIDs))
                        dismiss()
                    }) {
                        Text("Apply Categories")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.blue)
                            )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Button(action: {
                            selectedCategoryIDs.removeAll()
                        }) {
                            Text("Clear")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            newCategoryName = ""
                            showAddAlert = true
                        }) {
                            Label("New", systemImage: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(uiColor: .secondarySystemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("Edit Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("새 카테고리", isPresented: $showAddAlert) {
                TextField("카테고리 이름", text: $newCategoryName)
                Button("추가") {
                    if let created = onCreateCategory(newCategoryName) {
                        selectedCategoryIDs.insert(created.id)
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("카테고리 이름을 입력하세요.")
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selectedCategoryIDs.contains(id) {
            selectedCategoryIDs.remove(id)
        } else {
            selectedCategoryIDs.insert(id)
        }
    }
}

private struct DictionaryEntryCard: View {
    let entry: DictionaryEntry
    let categoryNames: [String]
    var leadingTopCaption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let leadingTopCaption, !leadingTopCaption.isEmpty {
                Text(leadingTopCaption)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

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
                categoryRow(
                    title: "전체",
                    count: chatStore.dictionaryEntryCount(for: .all),
                    isSelected: isSelected(.all)
                ) {
                    chatStore.setDictionaryCategoryFilter(.all)
                    dismiss()
                }
                categoryRow(
                    title: "미분류",
                    count: chatStore.dictionaryEntryCount(for: .uncategorized),
                    isSelected: isSelected(.uncategorized)
                ) {
                    chatStore.setDictionaryCategoryFilter(.uncategorized)
                    dismiss()
                }
            }

            if !chatStore.dictionaryCategories.isEmpty {
                Section("카테고리") {
                    ForEach(chatStore.dictionaryCategories) { category in
                        categoryRow(
                            title: category.name,
                            count: chatStore.dictionaryEntryCount(for: .category(category.id)),
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

    private func categoryRow(title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
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

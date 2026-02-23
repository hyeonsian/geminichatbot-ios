import SwiftUI
import PhotosUI
import UIKit

struct AIProfileEditorView: View {
    let conversationID: UUID

    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftVoicePreset = "Kore"
    @State private var draftAvatarImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    profileHeaderCard
                    voicePresetSection
                    clearHistorySection
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.blue)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(isEditing ? "저장" : "편집") {
                    if isEditing {
                        saveProfile()
                    } else {
                        isEditing = true
                    }
                }
                .foregroundStyle(Color.blue)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDraft()
        }
        .onChange(of: selectedPhotoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        draftAvatarImageData = data
                    }
                }
            }
        }
        .alert("대화 내역 지우기", isPresented: $showClearHistoryConfirmation) {
            Button("취소", role: .cancel) {}
            Button("지우기", role: .destructive) {
                chatStore.clearConversationHistory(for: conversationID)
            }
        } message: {
            Text("현재 채팅방의 대화 내역만 모두 삭제합니다. 사전에 저장된 항목은 삭제되지 않습니다.")
        }
    }

    private var profileHeaderCard: some View {
        VStack(spacing: 14) {
            if isEditing {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    profileAvatarView(size: 96)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.blue, Color.white)
                                .background(Color.white.clipShape(Circle()))
                        }
                }
                .buttonStyle(.plain)
            } else {
                profileAvatarView(size: 96)
            }

            if isEditing {
                TextField("AI Name", text: $draftName)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
            } else {
                Text(currentProfile.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.primary)
            }

            Text("Gemini 3 Flash")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }

    private var voicePresetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VOICE PRESET")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text("Choose TTS voice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Picker("Voice Preset", selection: $draftVoicePreset) {
                    ForEach(AIProfileSettings.supportedVoicePresets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .disabled(!isEditing)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.blue.opacity(0.08), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var clearHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHAT")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            Button(action: { showClearHistoryConfirmation = true }) {
                HStack {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .semibold))
                    Text("대화 내역 지우기")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Color.red)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.red.opacity(0.14), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currentProfile: AIProfileSettings {
        chatStore.aiProfile(for: conversationID)
    }

    @ViewBuilder
    private func profileAvatarView(size: CGFloat) -> some View {
        if let data = draftAvatarImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.30), Color.gray.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(initialLetter(from: draftName.isEmpty ? currentProfile.name : draftName))
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }

    private func initialLetter(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "A" }
        return String(first).uppercased()
    }

    private func loadDraft() {
        let profile = currentProfile
        draftName = profile.name
        draftVoicePreset = profile.voicePreset
        draftAvatarImageData = profile.avatarImageData
    }

    private func saveProfile() {
        chatStore.updateAIProfile(
            for: conversationID,
            name: draftName,
            avatarImageData: draftAvatarImageData,
            voicePreset: draftVoicePreset
        )
        isEditing = false
    }
}

#Preview {
    NavigationStack {
        AIProfileEditorView(conversationID: SampleData.conversations[0].id)
            .environmentObject(ChatStore())
    }
}

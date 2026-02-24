import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct AIProfileEditorView: View {
    let conversationID: UUID

    @EnvironmentObject private var chatStore: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var draftName = ""
    @State private var draftVoicePreset = "Kore"
    @State private var draftKoreanTranslationSpeechLevel: AIProfileSettings.KoreanTranslationSpeechLevel = .polite
    @State private var draftAvatarImageData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showClearHistoryConfirmation = false
    @State private var voicePreviewPlayer: AVAudioPlayer?
    @State private var isVoicePreviewLoading = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    profileHeaderCard
                    voicePresetSection
                    clearHistorySection
                    memoryDebugSection
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
        .onDisappear {
            stopVoicePreviewPlayback()
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
        .onChange(of: draftVoicePreset) { _ in
            guard isEditing else { return }
            playVoicePresetPreview()
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

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Choose TTS voice")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    if isVoicePreviewLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Picker("Voice Preset", selection: $draftVoicePreset) {
                        ForEach(AIProfileSettings.supportedVoicePresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(!isEditing)
                }

                Text("Selecting a voice plays a short preview.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: 8) {
                    Text("Korean translation tone")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Picker("Korean Translation Tone", selection: $draftKoreanTranslationSpeechLevel) {
                        ForEach(AIProfileSettings.KoreanTranslationSpeechLevel.allCases, id: \.self) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .disabled(!isEditing)
                }

                Text("Choose whether AI message translations appear in 존댓말 or 반말.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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

    private var memoryDebugSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONVERSATION MEMORY (DEBUG)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(memoryDebugStatusText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(memoryDebugStatusColor)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Refresh") {
                        chatStore.refreshConversationMemorySummaryNow(for: conversationID)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if conversationMemoryDebugSections.isEmpty && conversationMemoryDebugText.isEmpty {
                    Text("No memory saved yet.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    if !conversationMemoryDebugSections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(conversationMemoryDebugSections.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversationMemoryDebugSections[index].title.uppercased())
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.secondary)
                                    ForEach(conversationMemoryDebugSections[index].items, id: \.self) { item in
                                        Text("• \(item)")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                    } else {
                        Text(conversationMemoryDebugText)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
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

    private var currentProfile: AIProfileSettings {
        chatStore.aiProfile(for: conversationID)
    }

    private var conversationMemoryDebugText: String {
        chatStore.conversationMemorySummary(for: conversationID)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var conversationMemoryDebugSections: [(title: String, items: [String])] {
        chatStore.conversationMemoryProfile(for: conversationID).debugSections()
    }

    private var memoryDebugStatusText: String {
        let text = chatStore.conversationMemorySyncStatus(for: conversationID)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "No sync status yet." : text
    }

    private var memoryDebugStatusColor: Color {
        let lower = memoryDebugStatusText.lowercased()
        if lower.contains("failed") {
            return .red
        }
        if lower.contains("syncing") {
            return .orange
        }
        if lower.contains("succeeded") {
            return .green
        }
        return .secondary
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
        draftKoreanTranslationSpeechLevel = profile.koreanTranslationSpeechLevel
        draftAvatarImageData = profile.avatarImageData
    }

    private func saveProfile() {
        chatStore.updateAIProfile(
            for: conversationID,
            name: draftName,
            avatarImageData: draftAvatarImageData,
            voicePreset: draftVoicePreset,
            koreanTranslationSpeechLevel: draftKoreanTranslationSpeechLevel
        )
        isEditing = false
    }

    private func previewVoiceText() -> String {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty ? currentProfile.name : trimmedName
        return "Hi, I'm \(safeName). Nice to meet you."
    }

    private func playVoicePresetPreview() {
        stopVoicePreviewPlayback()
        isVoicePreviewLoading = true

        let text = previewVoiceText()
        let selectedVoice = draftVoicePreset

        Task {
            do {
                let audioData = try await BackendAPIClient.shared.ttsAudio(
                    text: text,
                    voiceName: selectedVoice
                )
                let player = try AVAudioPlayer(data: audioData)
                player.prepareToPlay()
                await MainActor.run {
                    self.voicePreviewPlayer = player
                    self.isVoicePreviewLoading = false
                    player.play()
                }
            } catch {
                await MainActor.run {
                    self.isVoicePreviewLoading = false
                }
            }
        }
    }

    private func stopVoicePreviewPlayback() {
        voicePreviewPlayer?.stop()
        voicePreviewPlayer = nil
        isVoicePreviewLoading = false
    }
}

#Preview {
    NavigationStack {
        AIProfileEditorView(conversationID: SampleData.conversations[0].id)
            .environmentObject(ChatStore())
    }
}

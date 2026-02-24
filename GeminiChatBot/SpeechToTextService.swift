import Foundation
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechToTextService: ObservableObject {
    enum SpeechToTextError: LocalizedError {
        case recognizerUnavailable
        case permissionDenied
        case audioEngineUnavailable

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable:
                return "Speech recognition is unavailable on this device."
            case .permissionDenied:
                return "Speech recognition and microphone permissions are required."
            case .audioEngineUnavailable:
                return "Audio input is unavailable."
            }
        }
    }

    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isManuallyStopping = false

    init(localeIdentifier: String = "en-US") {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    func clearError() {
        errorMessage = nil
    }

    func clearTranscript() {
        transcript = ""
    }

    func stopRecording() {
        guard isRecording else { return }
        isManuallyStopping = true
        finishRecognition()
    }

    func startRecording(initialText: String = "") {
        Task {
            do {
                clearError()
                try await ensurePermissions()
                try startRecognition(initialText: initialText)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                finishRecognition()
            }
        }
    }

    private func ensurePermissions() async throws {
        let speechAuthorized = await requestSpeechAuthorization()
        let micAuthorized = await requestMicrophoneAuthorization()
        guard speechAuthorized, micAuthorized else {
            throw SpeechToTextError.permissionDenied
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startRecognition(initialText: String) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechToTextError.recognizerUnavailable
        }

        finishRecognition()
        transcript = initialText
        isManuallyStopping = false

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishRecognition()
                    }
                }
                if let error {
                    if !self.isManuallyStopping {
                        self.errorMessage = error.localizedDescription
                    }
                    self.finishRecognition()
                }
            }
        }
    }

    private func finishRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

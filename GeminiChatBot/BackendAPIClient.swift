import Foundation

struct GrammarFeedbackResponse: Decodable {
    let hasErrors: Bool
    let correctedText: String
    let edits: [GrammarEdit]
    let feedback: String
    let feedbackPoints: [GrammarFeedbackPoint]
    let sentenceFeedback: [GrammarSentenceFeedback]
    let naturalAlternative: String
    let naturalReason: String
    let naturalRewrite: String

    struct GrammarEdit: Decodable, Hashable {
        let wrong: String
        let right: String
        let reason: String?
    }

    struct GrammarFeedbackPoint: Decodable, Hashable {
        let part: String
        let issue: String?
        let fix: String?
    }

    struct GrammarSentenceFeedback: Decodable, Hashable {
        let sentence: String
        let feedback: String
        let suggested: String?
        let why: String?
    }
}

struct NativeAlternativeItem: Decodable, Hashable, Identifiable {
    let id = UUID()
    let text: String
    let tone: String
    let nuance: String

    init(text: String, tone: String, nuance: String) {
        self.text = text
        self.tone = tone
        self.nuance = nuance
    }

    private enum CodingKeys: String, CodingKey {
        case text, tone, nuance
    }
}

private struct NativeAlternativesResponse: Decodable {
    let alternatives: [NativeAlternativeItem]
    let error: String?
}

private struct TranslateResponse: Decodable {
    let translation: String
}

private struct ChatResponse: Decodable {
    let reply: String
}

private struct BackendErrorResponse: Decodable {
    let error: String
}

private struct GrammarFeedbackRequest: Encodable {
    let text: String
    let model: String?
}

private struct NativeAlternativesRequest: Encodable {
    let text: String
    let model: String?
}

private struct TranslateRequest: Encodable {
    let text: String
    let targetLang: String
    let model: String?
}

private struct ChatRequest: Encodable {
    let message: String
    let model: String?
}

private struct TTSRequest: Encodable {
    let text: String
    let voiceName: String?
    let style: String?
}

enum BackendAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid backend response"
        case let .httpStatus(code, message):
            return "Backend error (\(code)): \(message)"
        case .emptyResponse:
            return "Empty response"
        }
    }
}

final class BackendAPIClient {
    static let shared = BackendAPIClient()

    /// Change this if you use a preview/staging deployment.
    var baseURLString: String = "https://imessage-gemini-chatbot.vercel.app"

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    func grammarFeedback(text: String, model: String? = nil) async throws -> GrammarFeedbackResponse {
        let req = GrammarFeedbackRequest(text: text, model: model)
        return try await post(path: "/api/grammar-feedback", body: req, responseType: GrammarFeedbackResponse.self)
    }

    func nativeAlternatives(text: String, model: String? = nil) async throws -> [NativeAlternativeItem] {
        let req = NativeAlternativesRequest(text: text, model: model)
        let response = try await post(path: "/api/native-alternatives", body: req, responseType: NativeAlternativesResponse.self)
        return response.alternatives
    }

    func translate(text: String, targetLang: String = "Korean", model: String? = nil) async throws -> String {
        let req = TranslateRequest(text: text, targetLang: targetLang, model: model)
        let response = try await post(path: "/api/translate", body: req, responseType: TranslateResponse.self)
        if response.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BackendAPIError.emptyResponse
        }
        return response.translation
    }

    func chatReply(message: String, model: String? = nil) async throws -> String {
        let req = ChatRequest(message: message, model: model)
        let response = try await post(path: "/api/chat", body: req, responseType: ChatResponse.self)
        let trimmed = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw BackendAPIError.emptyResponse }
        return trimmed
    }

    func ttsAudio(text: String, voiceName: String? = nil, style: String? = nil) async throws -> Data {
        let req = TTSRequest(text: text, voiceName: voiceName, style: style)
        return try await postRaw(path: "/api/tts", body: req, expectedContentTypePrefix: "audio/")
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: baseURLString + path) else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let backendError = try? decoder.decode(BackendErrorResponse.self, from: data)
            throw BackendAPIError.httpStatus(http.statusCode, backendError?.error ?? "Unknown error")
        }

        return try decoder.decode(responseType, from: data)
    }

    private func postRaw<Request: Encodable>(
        path: String,
        body: Request,
        expectedContentTypePrefix: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: baseURLString + path) else {
            throw BackendAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let backendError = try? decoder.decode(BackendErrorResponse.self, from: data)
            throw BackendAPIError.httpStatus(http.statusCode, backendError?.error ?? "Unknown error")
        }

        if let prefix = expectedContentTypePrefix?.lowercased(),
           let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
           !contentType.hasPrefix(prefix) {
            throw BackendAPIError.invalidResponse
        }

        if data.isEmpty {
            throw BackendAPIError.emptyResponse
        }
        return data
    }
}

import CoreImage
import Foundation

public struct OpenAICompatibleClient: Sendable {
    public var settings: RemoteAPISettings

    public init(settings: RemoteAPISettings) {
        self.settings = settings
    }

    public func listModels() async throws -> [String] {
        let (data, _) = try await request(path: "models", method: "GET", body: nil, timeout: 12)
        return Self.parseModelIDs(data)
    }

    public func transcribe(_ request: OCRRequest) async throws -> OCRResult {
        let jpeg = try ImageResizer.jpegData(
            request.image.cropped(to: request.image.extent),
            maxPixels: request.maxPixels
        )
        let model = try await resolvedModel(settings.ocrModel)
        let payload = ChatPayload(
            model: model,
            temperature: 0,
            maxTokens: request.maxTokens,
            messages: [
                .vision(text: OCRPrompt.text, jpeg: jpeg)
            ]
        )
        let started = ContinuousClock.now
        let raw = try await complete(payload)
        let text = OCREngine.stripThinking(raw)
        if text.isEmpty {
            throw OCREngineError.emptyOutput
        }
        return OCRResult(text: text, elapsed: ContinuousClock.now - started)
    }

    public func translate(_ request: TranslateRequest) async throws -> OCRResult {
        let model = try await resolvedModel(settings.translateModel)
        let payload = ChatPayload(
            model: model,
            temperature: 0,
            maxTokens: request.maxTokens,
            messages: [
                .text(TranslatePrompt.text(for: request))
            ]
        )
        let started = ContinuousClock.now
        let raw = try await complete(payload)
        let text = TranslatePrompt.cleaned(raw)
        if text.isEmpty {
            throw OCREngineError.emptyOutput
        }
        return OCRResult(text: text, elapsed: ContinuousClock.now - started)
    }

    public func ping() async throws -> [String] {
        try await listModels()
    }

    private func resolvedModel(_ preferred: String) async throws -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let ids = try await listModels()
        guard let first = ids.first else {
            throw OCREngineError.worker(
                "The remote server listed no models. Load a model in LM Studio, enable JIT loading, or pick a model id."
            )
        }
        return first
    }

    private func complete(_ payload: ChatPayload) async throws -> String {
        let body = try JSONEncoder().encode(payload)
        let (data, _) = try await request(path: "chat/completions", method: "POST", body: body)
        if let error = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error?.message,
           !error.isEmpty {
            throw OCREngineError.worker(error)
        }
        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let text = decoded.choices?.first?.message.content?.text ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        timeout: TimeInterval = 180
    ) async throws -> (Data, URLResponse) {
        guard settings.hasEndpoint, let url = URL(string: settings.normalizedBaseURL + "/" + path) else {
            throw OCREngineError.worker("Set a valid remote base URL, for example \(RemoteAPIStore.defaultBaseURL).")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = max(timeout, 300)
        config.waitsForConnectivity = false
        if Self.shouldBypassProxy(for: url) {
            config.connectionProxyDictionary = [
                "HTTPEnable": false,
                "HTTPSEnable": false,
                "SOCKSEnable": false,
            ]
        }
        let session = URLSession(configuration: config)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OCREngineError.worker(Self.describe(error, host: url.host))
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            if let message = (try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data))?.error?.message,
               !message.isEmpty {
                throw OCREngineError.worker(message)
            }
            let snippet = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = snippet.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: http.statusCode) : snippet
            throw OCREngineError.worker("Remote HTTP \(http.statusCode): \(detail)")
        }
        return (data, response)
    }

    static func parseModelIDs(_ data: Data) -> [String] {
        if let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) {
            let ids = decoded.data.map(\.id).filter { !$0.isEmpty }
            if !ids.isEmpty { return uniqued(ids) }
        }
        if let items = try? JSONDecoder().decode([ModelItem].self, from: data) {
            return uniqued(items.map(\.id).filter { !$0.isEmpty })
        }
        return []
    }

    private static func uniqued(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func shouldBypassProxy(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        if host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        let parts = host.split(separator: ".")
        if parts.count == 4, parts[0] == "172", let second = Int(parts[1]), (16...31).contains(second) {
            return true
        }
        return false
    }

    private static func describe(_ error: Error, host: String?) -> String {
        let host = host ?? "the remote server"
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet, NSURLErrorDNSLookupFailed:
                return "Could not reach \(host). Connect this Mac to the same LAN as LM Studio, then try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private struct ModelListResponse: Decodable {
    var data: [ModelItem]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([ModelItem].self, forKey: .data) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case data
    }
}

private struct ModelItem: Decodable {
    var id: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .id), !id.isEmpty {
            self.id = id
        } else if let name = try container.decodeIfPresent(String.self, forKey: .name), !name.isEmpty {
            self.id = name
        } else {
            self.id = ""
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

private struct OpenAIErrorEnvelope: Decodable {
    var error: OpenAIErrorBody?
}

private struct OpenAIErrorBody: Decodable {
    var message: String?
}

private struct ChatCompletionResponse: Decodable {
    var choices: [Choice]?

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: FlexibleContent?
    }
}

private struct FlexibleContent: Decodable {
    var text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
            return
        }
        if let parts = try? container.decode([Part].self) {
            text = parts.compactMap(\.text).joined()
            return
        }
        text = ""
    }

    struct Part: Decodable {
        var text: String?
    }
}

private struct ChatPayload: Encodable {
    var model: String
    var temperature: Double
    var maxTokens: Int
    var messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case maxTokens = "max_tokens"
        case messages
    }
}

private enum ChatMessage: Encodable {
    case text(String)
    case vision(text: String, jpeg: Data)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("user", forKey: .role)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .content)
        case .vision(let text, let jpeg):
            let dataURL = "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
            try container.encode(
                [
                    ContentPart(type: "text", text: text, imageURL: nil),
                    ContentPart(type: "image_url", text: nil, imageURL: .init(url: dataURL)),
                ],
                forKey: .content
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

private struct ContentPart: Encodable {
    var type: String
    var text: String?
    var imageURL: ImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        if let text {
            try container.encode(text, forKey: .text)
        }
        if let imageURL {
            try container.encode(imageURL, forKey: .imageURL)
        }
    }
}

private struct ImageURL: Encodable {
    var url: String
}

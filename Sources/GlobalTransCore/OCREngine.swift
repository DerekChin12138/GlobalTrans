import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM

public struct OCRRequest: Sendable {
    public var image: CIImage
    public var maxTokens: Int
    public var maxPixels: Int

    public init(image: CIImage, maxTokens: Int = 2048, maxPixels: Int = 1_638_400) {
        self.image = image
        self.maxTokens = maxTokens
        self.maxPixels = maxPixels
    }
}

public struct OCRResult: Sendable {
    public var text: String
    public var elapsed: Duration

    public init(text: String, elapsed: Duration) {
        self.text = text
        self.elapsed = elapsed
    }
}

public enum OCREngineError: LocalizedError {
    case emptyOutput
    case worker(String)

    public var errorDescription: String? {
        switch self {
        case .emptyOutput:
            return "The OCR model returned an empty string."
        case .worker(let message):
            return message
        }
    }
}

public struct TranslateRequest: Sendable {
    public var text: String
    public var chineseSource: Bool
    public var maxTokens: Int

    public init(text: String, chineseSource: Bool, maxTokens: Int = 4096) {
        self.text = text
        self.chineseSource = chineseSource
        self.maxTokens = maxTokens
    }
}

public enum OCRPrompt {
    public static let text = """
        Extract all readable content from the image in natural human reading order \
        and output the result as a single Markdown document. For charts or images, \
        represent them using an HTML image tag: <img src="images/bbox_{left}_{top}_{right}_{bottom}.jpg" />, \
        where left, top, right, bottom are bounding box coordinates scaled to [0, 1000). \
        Format formulas as LaTeX. Format tables as HTML: <table>...</table>. \
        Transcribe all other text as standard Markdown. Preserve the original text \
        without translation or paraphrasing.
        """
}

public actor OCREngine {
    private var container: ModelContainer?

    public init() {}

    public var isLoaded: Bool { container != nil }

    public func load(from directory: URL? = nil) async throws {
        if container != nil { return }
        MLXRuntime.configure()
        let modelDirectory = try directory ?? ModelLocator.modelDirectory()
        do {
            container = try await VLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: HuggingFaceTokenizerLoader()
            )
        } catch {
            throw OCREngineError.worker(error.localizedDescription)
        }
    }

    public func transcribe(_ request: OCRRequest) async throws -> OCRResult {
        if container == nil {
            try await load()
        }
        guard let container else {
            throw OCREngineError.worker("The OCR model is not loaded.")
        }

        let prepared = ImageResizer.capped(
            request.image.cropped(to: request.image.extent),
            maxPixels: request.maxPixels
        )

        let started = ContinuousClock.now
        let session = ChatSession(
            container,
            generateParameters: GenerateParameters(
                maxTokens: request.maxTokens,
                temperature: 0
            ),
            processing: UserInput.Processing(resize: nil, maxPixels: request.maxPixels),
            additionalContext: ["enable_thinking": false]
        )
        let raw: String
        do {
            raw = try await session.respond(
                to: OCRPrompt.text,
                image: .ciImage(prepared)
            )
        } catch {
            throw OCREngineError.worker(error.localizedDescription)
        }
        let text = OCREngine.stripThinking(raw)
        if text.isEmpty {
            throw OCREngineError.emptyOutput
        }
        MLXRuntime.releaseTemporaries()
        return OCRResult(text: text, elapsed: ContinuousClock.now - started)
    }

    public func unload() {
        container = nil
        Memory.clearCache()
    }

    nonisolated public static func stripThinking(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<think>") {
            if let end = trimmed.range(of: "</think>") {
                trimmed = String(trimmed[end.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return trimmed
    }
}

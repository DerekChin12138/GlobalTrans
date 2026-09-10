import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM

public struct OCRRequest: Sendable {
    public var jpeg: Data
    public var maxTokens: Int
    public var maxPixels: Int

    public init(jpeg: Data, maxTokens: Int = 2048, maxPixels: Int = OCRInputSettings.pixels(percent: OCRInputSettings.defaultPercent)) {
        self.jpeg = jpeg
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
    public var sourceLanguage: TranslateLanguage
    public var targetLanguage: TranslateLanguage
    public var maxTokens: Int

    public init(
        text: String,
        sourceLanguage: TranslateLanguage = .auto,
        targetLanguage: TranslateLanguage = .auto,
        maxTokens: Int = 4096
    ) {
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
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
        MLXRuntime.configure()
        guard let container else {
            throw OCREngineError.worker("The OCR model is not loaded.")
        }

        let started = ContinuousClock.now
        let parameters = GenerateParameters(
            maxTokens: request.maxTokens,
            temperature: 0
        )
        let raw: String
        do {
            // Single-shot generate so the KV cache dies with the stream.
            // Await the generation task before returning so Metal buffers can be cleared.
            raw = try await container.perform(values: request.jpeg) { context, jpeg in
                guard let prepared = ImageResizer.ciImage(fromJPEG: jpeg, maxPixels: request.maxPixels) else {
                    throw OCREngineError.worker("Could not decode the screenshot.")
                }
                let userInput = UserInput(
                    chat: [.user(OCRPrompt.text, images: [.ciImage(prepared)])],
                    processing: UserInput.Processing(resize: nil, maxPixels: request.maxPixels),
                    additionalContext: ["enable_thinking": false]
                )
                let input = try await context.processor.prepare(input: userInput)
                let iterator = try TokenIterator(
                    input: input,
                    model: context.model,
                    parameters: parameters
                )
                let (stream, task) = generateTask(
                    promptTokenCount: input.text.tokens.size,
                    modelConfiguration: context.configuration,
                    tokenizer: context.tokenizer,
                    iterator: iterator
                )
                var output = ""
                for await item in stream {
                    if let chunk = item.chunk {
                        output += chunk
                    }
                }
                await task.value
                return output
            }
        } catch {
            MLXRuntime.releaseAll()
            throw OCREngineError.worker(error.localizedDescription)
        }
        let text = OCREngine.stripThinking(raw)
        if text.isEmpty {
            throw OCREngineError.emptyOutput
        }
        MLXRuntime.releaseAll()
        return OCRResult(text: text, elapsed: ContinuousClock.now - started)
    }

    public func unload() async {
        container = nil
        await Task.yield()
        MLXRuntime.releaseAll()
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

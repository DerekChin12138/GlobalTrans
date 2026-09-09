import Foundation
import MLX
import MLXLLM
import MLXLMCommon

public actor TranslationEngine {
    private var container: ModelContainer?

    public init() {}

    public var isLoaded: Bool { container != nil }

    public func load(from directory: URL? = nil) async throws {
        if container != nil { return }
        MLXRuntime.configure()
        await Self.registerArchitecture()
        let modelDirectory = try directory ?? ModelLocator.translationDirectory()
        do {
            container = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: HuggingFaceTokenizerLoader()
            )
        } catch {
            throw OCREngineError.worker(error.localizedDescription)
        }
    }

    public func translate(_ request: TranslateRequest) async throws -> OCRResult {
        if container == nil {
            try await load()
        }
        guard let container else {
            throw OCREngineError.worker("The translation model is not loaded.")
        }

        let started = ContinuousClock.now
        let wrapped = HunyuanChat.wrap(TranslatePrompt.text(for: request))
        let parameters = GenerateParameters(maxTokens: request.maxTokens, temperature: 0)
        let raw: String
        do {
            raw = try await container.perform { context in
                var tokenIds = context.tokenizer.encode(text: wrapped, addSpecialTokens: false)
                tokenIds = HunyuanChat.mergeSplitNewlines(tokenIds, tokenizer: context.tokenizer)
                let input = LMInput(tokens: MLXArray(tokenIds))
                let stream = try generate(input: input, parameters: parameters, context: context)
                var output = ""
                for await item in stream {
                    if let chunk = item.chunk {
                        output += chunk
                    }
                }
                return output
            }
        } catch {
            throw OCREngineError.worker(error.localizedDescription)
        }
        let text = TranslatePrompt.cleaned(raw)
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

    private static func registerArchitecture() async {
        if await LLMTypeRegistry.shared.contains("hunyuan_v1_dense") { return }
        await LLMTypeRegistry.shared.registerModelType("hunyuan_v1_dense") { data in
            let config = try JSONDecoder.json5().decode(HunyuanV1DenseConfiguration.self, from: data)
            return HunyuanV1DenseModel(config)
        }
    }
}

enum HunyuanChat {
    /// Hunyuan chat string, encoded as a whole so BPE merges match Python mlx-lm.
    static func wrap(_ user: String) -> String {
        "<｜hy_begin▁of▁sentence｜><｜hy_User｜>\(user)<｜hy_Assistant｜>"
    }

    /// swift-transformers splits `:\n\n` into `:` + `\n\n`. Python BPE keeps a single fused token.
    static func mergeSplitNewlines(_ tokens: [Int], tokenizer: Tokenizer) -> [Int] {
        let colon = tokenizer.convertTokenToId(":") ?? 25
        let blank = tokenizer.convertTokenToId("\n\n") ?? 286
        let fused = tokenizer.convertTokenToId(":\n\n") ?? 1015
        var merged: [Int] = []
        merged.reserveCapacity(tokens.count)
        var index = 0
        while index < tokens.count {
            if index + 1 < tokens.count, tokens[index] == colon, tokens[index + 1] == blank {
                merged.append(fused)
                index += 2
            } else {
                merged.append(tokens[index])
                index += 1
            }
        }
        return merged
    }
}

public enum TranslatePrompt {
    public static func text(for request: TranslateRequest) -> String {
        if request.chineseSource {
            return """
                Translate the following text into English. Note that you should only output the translated result without any additional explanation:

                \(request.text)
                """
        }
        return """
            将以下文本翻译为简体中文，注意只需要输出翻译后的结果，不要额外解释：

            \(request.text)
            """
    }

    public static func cleaned(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<think>") {
            if let end = text.range(of: "</think>") {
                text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 3, lines.last?.hasPrefix("```") == true {
                text = lines.dropFirst().dropLast().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for prefix in ["Translation:", "译文：", "翻译："] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}

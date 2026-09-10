import Foundation
import GlobalTransCore

@main
struct GTOCRCLI {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--translate" {
            let text = args.dropFirst().joined(separator: " ")
            guard !text.isEmpty else {
                fputs("usage: gt-ocr-cli --translate <text>\n", stderr)
                exit(2)
            }
            try await runTranslate(text)
            return
        }
        guard let path = args.first else {
            fputs("usage: gt-ocr-cli <image.png>\n       gt-ocr-cli --translate <text>\n", stderr)
            exit(2)
        }
        let url = URL(filePath: path)
        let jpeg = try Data(contentsOf: url)
        let engine = OCREngine()
        let result = try await engine.transcribe(OCRRequest(jpeg: jpeg))
        print(result.text)
        print(
            "\n---\nelapsed \(format(result.elapsed))",
            terminator: "\n"
        )
        await engine.unload()
    }

    static func runTranslate(_ text: String) async throws {
        let engine = TranslationEngine()
        let result = try await engine.translate(
            TranslateRequest(text: text, maxTokens: 256)
        )
        print(result.text)
        print("\n---\nelapsed \(format(result.elapsed))", terminator: "\n")
        await engine.unload()
    }

    static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2fs", seconds)
    }
}

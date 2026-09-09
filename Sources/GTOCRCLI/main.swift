import CoreImage
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
        guard let image = loadCIImage(url) else {
            throw CLIError.unreadableImage(url)
        }
        let engine = OCREngine()
        let result = try await engine.transcribe(OCRRequest(image: image))
        print(result.text)
        print(
            "\n---\nelapsed \(format(result.elapsed))",
            terminator: "\n"
        )
        await engine.unload()
    }

    static func runTranslate(_ text: String) async throws {
        let chineseSource = text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        let engine = TranslationEngine()
        let result = try await engine.translate(
            TranslateRequest(text: text, chineseSource: chineseSource, maxTokens: 256)
        )
        print(result.text)
        print("\n---\nelapsed \(format(result.elapsed))", terminator: "\n")
        await engine.unload()
    }

    static func loadCIImage(_ url: URL) -> CIImage? {
        CIImage(contentsOf: url)
    }

    static func format(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.2fs", seconds)
    }
}

enum CLIError: LocalizedError {
    case unreadableImage(URL)

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url):
            return "Could not read image at \(url.path)"
        }
    }
}

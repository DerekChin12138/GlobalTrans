import Foundation

/// SwiftMath (iosMath) only understands a TeX subset. OCR often emits amsmath
/// that it rejects with "Invalid command \…". Rewrite those before rendering.
enum MathLatex {
    static func sanitized(_ latex: String) -> String {
        var text = latex
        text = rewriteExtensibleArrow(text, command: "xrightarrow", replacement: "longrightarrow")
        text = rewriteExtensibleArrow(text, command: "xleftarrow", replacement: "longleftarrow")
        return text
    }

    /// `\xrightarrow{d}` → `\longrightarrow^{d}`
    private static func rewriteExtensibleArrow(_ latex: String, command: String, replacement: String) -> String {
        let needle = "\\\(command){"
        var result = ""
        var rest = latex[...]
        while let start = rest.range(of: needle) {
            result += rest[..<start.lowerBound]
            let after = start.upperBound
            guard let close = rest[after...].firstIndex(of: "}") else {
                result += rest[start.lowerBound...]
                return result
            }
            let arg = rest[after..<close]
            result += "\\\(replacement)^{\(arg)}"
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

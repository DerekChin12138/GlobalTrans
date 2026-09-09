import Foundation

enum MathEmbed {
    static let scheme = "gtmath"

    struct Payload: Equatable {
        var latex: String
        var fontSize: CGFloat
        var dark: Bool
    }

    static func markdownImage(latex: String, fontSize: CGFloat, dark: Bool) -> String {
        guard let url = encode(latex: latex, fontSize: fontSize, dark: dark) else {
            return latex
        }
        return "![](\(url))"
    }

    static func encode(latex: String, fontSize: CGFloat, dark: Bool) -> String? {
        let payload = Data(latex.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var components = URLComponents()
        components.scheme = scheme
        components.host = "m"
        components.path = "/" + payload
        components.queryItems = [
            URLQueryItem(name: "s", value: String(Int(fontSize.rounded()))),
            URLQueryItem(name: "d", value: dark ? "1" : "0"),
        ]
        return components.string
    }

    static func decode(_ url: URL) -> Payload? {
        guard url.scheme == scheme else { return nil }
        var payload = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if payload.isEmpty, let host = url.host, host != "m" {
            payload = host
        }
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - payload.count % 4) % 4
        payload += String(repeating: "=", count: pad)
        guard let data = Data(base64Encoded: payload),
              let latex = String(data: data, encoding: .utf8),
              !latex.isEmpty
        else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let fontSize = CGFloat(Int(items?.first(where: { $0.name == "s" })?.value ?? "") ?? 13)
        let dark = items?.first(where: { $0.name == "d" })?.value == "1"
        return Payload(latex: latex, fontSize: max(fontSize, 10), dark: dark)
    }
}

enum MarkdownPreviewText {
    enum Segment: Equatable {
        case markdown(String)
        case displayMath(String)
    }

    static func prepared(_ raw: String) -> String {
        var text = stripPlaceholderImages(raw)
        text = repairJammedHTMLTags(text)
        text = convertHTMLTables(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func segments(from raw: String, fontSize: CGFloat = 13, dark: Bool = false) -> [Segment] {
        let text = prepared(raw)
        guard !text.isEmpty else { return [] }
        var segments: [Segment] = []
        var index = text.startIndex
        var markdownStart = index

        func flushMarkdown(upTo end: String.Index) {
            guard markdownStart < end else { return }
            let chunk = String(text[markdownStart..<end])
            if !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdown(embedInlineMath(chunk, fontSize: fontSize, dark: dark)))
            }
        }

        while index < text.endIndex {
            if let end = skipFence(in: text, from: index) {
                index = end
                continue
            }
            if let end = skipInlineCode(in: text, from: index) {
                index = end
                continue
            }
            if let match = matchDisplayMath(in: text, from: index) {
                flushMarkdown(upTo: match.range.lowerBound)
                let latex = match.latex.trimmingCharacters(in: .whitespacesAndNewlines)
                if !latex.isEmpty {
                    segments.append(.displayMath(latex))
                }
                index = match.range.upperBound
                markdownStart = index
                continue
            }
            index = text.index(after: index)
        }
        flushMarkdown(upTo: text.endIndex)
        return segments
    }

    private struct MathMatch {
        var range: Range<String.Index>
        var latex: String
    }

    private static func matchDisplayMath(in text: String, from start: String.Index) -> MathMatch? {
        let rest = text[start...]
        if rest.hasPrefix("$$"), let close = text.range(of: "$$", range: text.index(start, offsetBy: 2)..<text.endIndex) {
            return MathMatch(
                range: start..<close.upperBound,
                latex: String(text[text.index(start, offsetBy: 2)..<close.lowerBound])
            )
        }
        if rest.hasPrefix("\\["), let close = text.range(of: "\\]", range: text.index(start, offsetBy: 2)..<text.endIndex) {
            return MathMatch(
                range: start..<close.upperBound,
                latex: String(text[text.index(start, offsetBy: 2)..<close.lowerBound])
            )
        }
        return nil
    }

    static func embedInlineMath(_ text: String, fontSize: CGFloat, dark: Bool) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            if let end = skipFence(in: text, from: index) {
                result += text[index..<end]
                index = end
                continue
            }
            if let end = skipInlineCode(in: text, from: index) {
                result += text[index..<end]
                index = end
                continue
            }
            if let match = matchInlineMath(in: text, from: index) {
                let latex = match.latex.trimmingCharacters(in: .whitespacesAndNewlines)
                if latex.isEmpty {
                    result += text[match.range]
                } else {
                    result += MathEmbed.markdownImage(latex: latex, fontSize: fontSize, dark: dark)
                }
                index = match.range.upperBound
                continue
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func matchInlineMath(in text: String, from start: String.Index) -> MathMatch? {
        let rest = text[start...]
        if rest.hasPrefix("\\("), let close = text.range(of: "\\)", range: text.index(start, offsetBy: 2)..<text.endIndex) {
            return MathMatch(
                range: start..<close.upperBound,
                latex: String(text[text.index(start, offsetBy: 2)..<close.lowerBound])
            )
        }
        if rest.hasPrefix("$"), !rest.hasPrefix("$$") {
            let after = text.index(after: start)
            if let close = text[after...].firstIndex(of: "$"),
               close > after,
               text[after..<close].contains(where: { $0.isNewline }) == false,
               !(close < text.index(before: text.endIndex) && text[text.index(after: close)] == "$")
            {
                return MathMatch(
                    range: start..<text.index(after: close),
                    latex: String(text[after..<close])
                )
            }
        }
        return nil
    }

    private static func skipFence(in text: String, from start: String.Index) -> String.Index? {
        guard text[start...].hasPrefix("```") else { return nil }
        let afterOpen = text.index(start, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
        if let close = text.range(of: "```", range: afterOpen..<text.endIndex) {
            return close.upperBound
        }
        return text.endIndex
    }

    private static func skipInlineCode(in text: String, from start: String.Index) -> String.Index? {
        guard text[start] == "`" else { return nil }
        var ticks = 0
        var index = start
        while index < text.endIndex, text[index] == "`" {
            ticks += 1
            index = text.index(after: index)
        }
        guard ticks > 0, index < text.endIndex else { return nil }
        let marker = String(repeating: "`", count: ticks)
        if let close = text.range(of: marker, range: index..<text.endIndex) {
            return close.upperBound
        }
        return nil
    }

    private static func stripPlaceholderImages(_ text: String) -> String {
        let patterns = [
            #"<img[^>]*src=["']images/bbox_[^"']+["'][^>]*/?>"#,
            #"<img[^>]*src=["']images/bbox_[^"']+["'][^>]*>\s*</img>"#,
        ]
        var result = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
        }
        return result
    }

    /// OvisOCR2-4bit often drops `>` between adjacent tags (`</td><td>` → `</td<td>`).
    private static func repairJammedHTMLTags(_ text: String) -> String {
        guard text.localizedCaseInsensitiveContains("<table") else { return text }
        let pattern = #"</?(?:table|thead|tbody|tfoot|tr|td|th|caption)(?:\s[^<>]*?)?(?=<)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        var current = text
        for _ in 0..<8 {
            let ns = current as NSString
            let matches = regex.matches(in: current, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { break }
            var next = current
            for match in matches.reversed() {
                var tag = ns.substring(with: match.range)
                if tag.filter({ $0 == "\"" }).count % 2 == 1 {
                    tag += "\""
                }
                tag += ">"
                next = (next as NSString).replacingCharacters(in: match.range, with: tag)
            }
            if next == current { break }
            current = next
        }
        return current
    }

    private static func convertHTMLTables(_ markdown: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<table\b[\s\S]*?</table>"#,
            options: [.caseInsensitive]
        ) else {
            return markdown
        }
        let ns = markdown as NSString
        var result = markdown
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let html = ns.substring(with: match.range)
            let converted = htmlTableToMarkdown(html) ?? html
            result = (result as NSString).replacingCharacters(in: match.range, with: "\n\n\(converted)\n\n")
        }
        return result
    }

    private static func htmlTableToMarkdown(_ html: String) -> String? {
        guard let rowRegex = try? NSRegularExpression(
            pattern: #"<tr\b[\s\S]*?</tr>"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let ns = html as NSString
        let rowMatches = rowRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var rows: [[String]] = []
        for rowMatch in rowMatches {
            let rowHTML = ns.substring(with: rowMatch.range)
            let cells = cells(in: rowHTML)
            if !cells.isEmpty {
                rows.append(cells)
            }
        }
        guard let header = rows.first, !header.isEmpty else { return nil }
        var normalized = rows
        let width = max(header.count, rows.map(\.count).max() ?? 0)
        if header.count == width - 1, rows.dropFirst().contains(where: { $0.count == width }) {
            normalized[0] = [""] + header
        }
        let padded = normalized.map { row -> [String] in
            if row.count >= width { return Array(row.prefix(width)) }
            return row + Array(repeating: "", count: width - row.count)
        }
        var lines: [String] = []
        lines.append("| " + padded[0].joined(separator: " | ") + " |")
        lines.append("| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |")
        for row in padded.dropFirst() {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }

    private static func cells(in rowHTML: String) -> [String] {
        guard let cellRegex = try? NSRegularExpression(
            pattern: #"<t[hd]\b[^>]*>([\s\S]*?)</t[hd]>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let ns = rowHTML as NSString
        return cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: ns.length)).map { match in
            guard match.numberOfRanges > 1 else { return "" }
            return cleanupCell(ns.substring(with: match.range(at: 1)))
        }
    }

    private static func cleanupCell(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "$$", with: "$")
        text = text.replacingOccurrences(of: "$true", with: "$ true")
        text = text.replacingOccurrences(of: "$false", with: "$ false")
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: .regularExpression)
        if let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = tagRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&mdash;", "—"),
            ("&#8212;", "—"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

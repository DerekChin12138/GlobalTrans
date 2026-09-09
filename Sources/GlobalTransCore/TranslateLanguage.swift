import Foundation

public enum TranslateLanguage: String, CaseIterable, Identifiable, Sendable {
    case auto
    case simplifiedChinese
    case traditionalChinese
    case english
    case japanese
    case korean
    case french
    case german
    case spanish
    case russian
    case portuguese
    case italian
    case arabic
    case vietnamese
    case thai
    case indonesian
    case hindi

    public var id: String { rawValue }

    public var menuLabel: String {
        switch self {
        case .auto: return "Auto"
        case .simplifiedChinese: return "Chinese (Simplified)"
        case .traditionalChinese: return "Chinese (Traditional)"
        case .english: return "English"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        case .russian: return "Russian"
        case .portuguese: return "Portuguese"
        case .italian: return "Italian"
        case .arabic: return "Arabic"
        case .vietnamese: return "Vietnamese"
        case .thai: return "Thai"
        case .indonesian: return "Indonesian"
        case .hindi: return "Hindi"
        }
    }

    public var isChinese: Bool {
        self == .simplifiedChinese || self == .traditionalChinese
    }

    public func officialName(chinesePrompt: Bool) -> String {
        switch self {
        case .auto:
            return ""
        case .simplifiedChinese:
            return chinesePrompt ? "简体中文" : "Simplified Chinese"
        case .traditionalChinese:
            return chinesePrompt ? "繁体中文" : "Traditional Chinese"
        case .english:
            return chinesePrompt ? "英语" : "English"
        case .japanese:
            return chinesePrompt ? "日语" : "Japanese"
        case .korean:
            return chinesePrompt ? "韩语" : "Korean"
        case .french:
            return chinesePrompt ? "法语" : "French"
        case .german:
            return chinesePrompt ? "德语" : "German"
        case .spanish:
            return chinesePrompt ? "西班牙语" : "Spanish"
        case .russian:
            return chinesePrompt ? "俄语" : "Russian"
        case .portuguese:
            return chinesePrompt ? "葡萄牙语" : "Portuguese"
        case .italian:
            return chinesePrompt ? "意大利语" : "Italian"
        case .arabic:
            return chinesePrompt ? "阿拉伯语" : "Arabic"
        case .vietnamese:
            return chinesePrompt ? "越南语" : "Vietnamese"
        case .thai:
            return chinesePrompt ? "泰语" : "Thai"
        case .indonesian:
            return chinesePrompt ? "印尼语" : "Indonesian"
        case .hindi:
            return chinesePrompt ? "印地语" : "Hindi"
        }
    }

    public static func looksChinese(_ text: String) -> Bool {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                cjk += 1
            } else if CharacterSet.letters.contains(scalar) {
                latin += 1
            }
        }
        return cjk >= 8 || (cjk > 0 && cjk >= latin / 2)
    }

    public static func resolve(
        source: TranslateLanguage,
        target: TranslateLanguage,
        text: String
    ) -> (source: TranslateLanguage, target: TranslateLanguage, sourceExplicit: Bool) {
        let detected: TranslateLanguage = looksChinese(text) ? .simplifiedChinese : .english
        let resolvedSource = source == .auto ? detected : source
        let resolvedTarget: TranslateLanguage
        if target == .auto {
            resolvedTarget = resolvedSource.isChinese ? .english : .simplifiedChinese
        } else {
            resolvedTarget = target
        }
        return (resolvedSource, resolvedTarget, source != .auto)
    }
}

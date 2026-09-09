import Foundation

enum LanguageGuess {
    case chinese
    case english
    case other

    static func detect(_ text: String) -> LanguageGuess {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) {
                cjk += 1
            } else if CharacterSet.letters.contains(scalar) {
                latin += 1
            }
        }
        if cjk >= 8 || (cjk > 0 && cjk >= latin / 2) {
            return .chinese
        }
        if latin >= 12 {
            return .english
        }
        return .other
    }
}

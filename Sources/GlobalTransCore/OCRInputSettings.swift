import Foundation

/// OvisOCR2 official image budget: 448×448 ... 2880×2880.
public enum OCRInputSettings {
    public static let officialMinPixels = 448 * 448
    public static let officialMaxPixels = 2880 * 2880
    public static let defaultPercent = 0.20
    public static let minPercent = 0.10
    public static let maxPercent = 1.0

    public static func clampedPercent(_ value: Double) -> Double {
        min(max(value, minPercent), maxPercent)
    }

    public static func pixels(percent: Double) -> Int {
        let fraction = clampedPercent(percent)
        let value = Int((Double(officialMaxPixels) * fraction).rounded())
        return max(min(value, officialMaxPixels), officialMinPixels)
    }

    public static func maxTokens(percent: Double) -> Int {
        pixels(percent: percent) >= 4_000_000 ? 4096 : 2048
    }

    public static func megapixelsLabel(_ pixels: Int) -> String {
        String(format: "%.1fMP", Double(pixels) / 1_000_000)
    }
}

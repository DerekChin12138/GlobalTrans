import Foundation

public struct RemoteAPISettings: Sendable, Equatable {
    public var useRemoteOCR: Bool
    public var useRemoteTranslate: Bool
    public var baseURL: String
    public var apiKey: String
    public var ocrModel: String
    public var translateModel: String

    public init(
        useRemoteOCR: Bool = false,
        useRemoteTranslate: Bool = false,
        baseURL: String = "",
        apiKey: String = "",
        ocrModel: String = "",
        translateModel: String = ""
    ) {
        self.useRemoteOCR = useRemoteOCR
        self.useRemoteTranslate = useRemoteTranslate
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.ocrModel = ocrModel
        self.translateModel = translateModel
    }

    public var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    public var displayHost: String {
        let value = normalizedBaseURL
        return value.isEmpty ? "(not set)" : value
    }

    public var hasEndpoint: Bool {
        URL(string: normalizedBaseURL) != nil && normalizedBaseURL.lowercased().hasPrefix("http")
    }
}

public enum RemoteAPIStore {
    public static let defaultBaseURL = "http://127.0.0.1:1234/v1"

    private static let useOCRKey = "GTRemoteUseOCR"
    private static let useTranslateKey = "GTRemoteUseTranslate"
    private static let baseURLKey = "GTRemoteBaseURL"
    private static let apiKeyKey = "GTRemoteAPIKey"
    private static let ocrModelKey = "GTRemoteOCRModel"
    private static let translateModelKey = "GTRemoteTranslateModel"

    public static func load() -> RemoteAPISettings {
        let defaults = UserDefaults.standard
        return RemoteAPISettings(
            useRemoteOCR: defaults.bool(forKey: useOCRKey),
            useRemoteTranslate: defaults.bool(forKey: useTranslateKey),
            baseURL: defaults.string(forKey: baseURLKey) ?? "",
            apiKey: defaults.string(forKey: apiKeyKey) ?? "",
            ocrModel: defaults.string(forKey: ocrModelKey) ?? "",
            translateModel: defaults.string(forKey: translateModelKey) ?? ""
        )
    }

    public static func save(_ settings: RemoteAPISettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.useRemoteOCR, forKey: useOCRKey)
        defaults.set(settings.useRemoteTranslate, forKey: useTranslateKey)
        defaults.set(settings.baseURL, forKey: baseURLKey)
        defaults.set(settings.apiKey, forKey: apiKeyKey)
        defaults.set(settings.ocrModel, forKey: ocrModelKey)
        defaults.set(settings.translateModel, forKey: translateModelKey)
    }
}

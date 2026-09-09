import Foundation

public enum ModelLocatorError: LocalizedError {
    case notFound([URL])

    public var errorDescription: String? {
        switch self {
        case .notFound(let urls):
            let listed = urls.map(\.path).joined(separator: "\n")
            return "Local model not found. Looked in:\n\(listed)"
        }
    }
}

public enum ModelLocator {
    public static let savedModelPathKey = "GTModelPath"
    public static let savedTranslationPathKey = "GTTranslationPath"

    public static func expandPath(_ raw: String) -> String {
        (raw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
    }

    public static func url(fromPath raw: String) -> URL {
        URL(filePath: expandPath(raw), directoryHint: .isDirectory)
    }

    public static func setSavedModelDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: savedModelPathKey)
    }

    public static func setSavedTranslationDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: savedTranslationPathKey)
    }

    public static func clearSavedModelDirectory() {
        UserDefaults.standard.removeObject(forKey: savedModelPathKey)
    }

    public static func clearSavedTranslationDirectory() {
        UserDefaults.standard.removeObject(forKey: savedTranslationPathKey)
    }

    public static func savedOCRPath() -> String {
        UserDefaults.standard.string(forKey: savedModelPathKey) ?? ""
    }

    public static func savedTranslationPath() -> String {
        UserDefaults.standard.string(forKey: savedTranslationPathKey) ?? ""
    }

    public static func configuredOCRPath() -> String {
        let saved = savedOCRPath()
        if !saved.isEmpty { return abbreviated(saved) }
        if let url = try? modelDirectory() { return abbreviated(url.path) }
        return ""
    }

    public static func configuredTranslationPath() -> String {
        let saved = savedTranslationPath()
        if !saved.isEmpty { return abbreviated(saved) }
        if let url = try? translationDirectory() { return abbreviated(url.path) }
        return ""
    }

    public static func repositoryRoot(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath)
    ) throws -> URL {
        if let override = environment["GT_ROOT"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        if let marker = Bundle.main.url(forResource: "workspace-root", withExtension: nil),
           let path = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty
        {
            let url = URL(filePath: path, directoryHint: .isDirectory)
            if isRepoRoot(url, fileManager: fileManager) {
                return url
            }
        }
        var candidates = [
            currentDirectory,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ]
        if let model = environment["GT_MODEL_PATH"], !model.isEmpty {
            candidates.insert(URL(filePath: model).deletingLastPathComponent(), at: 0)
        }
        let resolved = candidates.map(\.standardizedFileURL)
        if let match = resolved.first(where: { isRepoRoot($0, fileManager: fileManager) }) {
            return match
        }
        throw ModelLocatorError.notFound(resolved)
    }

    public static func dataDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["GT_DATA_PATH"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "GlobalTrans", directoryHint: .isDirectory)
    }

    public static func modelDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment["GT_MODEL_PATH"], !override.isEmpty {
            let url = url(fromPath: override)
            if let resolved = resolveOCRDirectory(url, fileManager: fileManager) {
                return resolved
            }
            throw ModelLocatorError.notFound([url])
        }
        let saved = savedOCRPath()
        if !saved.isEmpty {
            let url = url(fromPath: saved)
            if let resolved = resolveOCRDirectory(url, fileManager: fileManager) {
                return resolved
            }
            throw ModelLocatorError.notFound([url])
        }
        let candidates = ocrSearchCandidates(fileManager: fileManager, environment: environment)
        if let match = candidates.first(where: { isModelDirectory($0, fileManager: fileManager) }) {
            return match
        }
        throw ModelLocatorError.notFound(candidates)
    }

    public static func translationDirectory(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment["GT_TRANSLATION_PATH"], !override.isEmpty {
            let url = url(fromPath: override)
            if let resolved = resolveTranslationDirectory(url, fileManager: fileManager) {
                return resolved
            }
            throw ModelLocatorError.notFound([url])
        }
        let saved = savedTranslationPath()
        if !saved.isEmpty {
            let url = url(fromPath: saved)
            if let resolved = resolveTranslationDirectory(url, fileManager: fileManager) {
                return resolved
            }
            throw ModelLocatorError.notFound([url])
        }
        let candidates = translationSearchCandidates(fileManager: fileManager, environment: environment)
        if let match = candidates.first(where: { isModelDirectory($0, fileManager: fileManager) }) {
            return match
        }
        throw ModelLocatorError.notFound(candidates)
    }

    public static func resolveOCRDirectory(_ url: URL, fileManager: FileManager = .default) -> URL? {
        if isModelDirectory(url, fileManager: fileManager) { return url }
        let nested = url.appending(path: "OvisOCR2-4bit", directoryHint: .isDirectory)
        if isModelDirectory(nested, fileManager: fileManager) { return nested }
        return nil
    }

    public static func resolveTranslationDirectory(_ url: URL, fileManager: FileManager = .default) -> URL? {
        if isModelDirectory(url, fileManager: fileManager) { return url }
        for name in ["Hy-MT2-1.8B-4bit", "Hy-MT2-1.8b-4bit"] {
            let nested = url.appending(path: name, directoryHint: .isDirectory)
            if isModelDirectory(nested, fileManager: fileManager) { return nested }
        }
        return nil
    }

    public static func abbreviated(_ path: String) -> String {
        let expanded = expandPath(path)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if expanded.hasPrefix(home) {
            return "~" + expanded.dropFirst(home.count)
        }
        return expanded
    }

    public static func ocrDisplayPath() -> String {
        if let url = try? modelDirectory() {
            return abbreviated(url.path)
        }
        let saved = savedOCRPath()
        if !saved.isEmpty { return abbreviated(saved) + " (missing)" }
        return "OCR model not set"
    }

    public static func translationDisplayPath() -> String {
        if let url = try? translationDirectory() {
            return abbreviated(url.path)
        }
        let saved = savedTranslationPath()
        if !saved.isEmpty { return abbreviated(saved) + " (missing)" }
        return "translation model not set"
    }

    public static func isModelDirectory(_ url: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: url.appending(path: "config.json").path)
            && fileManager.fileExists(atPath: url.appending(path: "model.safetensors").path)
    }

    public static func portableRoots(fileManager: FileManager = .default) -> [URL] {
        var roots: [URL] = []
        let app = Bundle.main.bundleURL
        roots.append(app.deletingLastPathComponent())
        roots.append(app.deletingLastPathComponent().appending(path: "Models", directoryHint: .isDirectory))
        if let resources = Bundle.main.resourceURL {
            roots.append(resources)
            roots.append(resources.appending(path: "Models", directoryHint: .isDirectory))
        }
        roots.append(dataDirectory(fileManager: fileManager))
        let applications = fileManager.homeDirectoryForCurrentUser
            .appending(path: "Applications", directoryHint: .isDirectory)
        roots.append(applications)
        roots.append(applications.appending(path: "GlobalTrans", directoryHint: .isDirectory))
        return roots
    }

    private static func ocrSearchCandidates(
        fileManager: FileManager,
        environment: [String: String]
    ) -> [URL] {
        var candidates: [URL] = []
        for root in portableRoots(fileManager: fileManager) {
            candidates.append(root.appending(path: "OvisOCR2-4bit", directoryHint: .isDirectory))
            candidates.append(root)
        }
        if let repo = try? repositoryRoot(fileManager: fileManager, environment: environment) {
            candidates.append(repo.appending(path: "OvisOCR2-4bit", directoryHint: .isDirectory))
        }
        return uniqued(candidates)
    }

    private static func translationSearchCandidates(
        fileManager: FileManager,
        environment: [String: String]
    ) -> [URL] {
        var candidates: [URL] = []
        for root in portableRoots(fileManager: fileManager) {
            candidates.append(root.appending(path: "Hy-MT2-1.8B-4bit", directoryHint: .isDirectory))
            candidates.append(root.appending(path: "Hy-MT2-1.8b-4bit", directoryHint: .isDirectory))
            candidates.append(root)
        }
        if let repo = try? repositoryRoot(fileManager: fileManager, environment: environment) {
            candidates.append(repo.appending(path: "Hy-MT2-1.8B-4bit", directoryHint: .isDirectory))
            candidates.append(repo.appending(path: "Hy-MT2-1.8b-4bit", directoryHint: .isDirectory))
        }
        return uniqued(candidates)
    }

    private static func uniqued(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func isRepoRoot(_ url: URL, fileManager: FileManager) -> Bool {
        isModelDirectory(url.appending(path: "OvisOCR2-4bit"), fileManager: fileManager)
    }
}

import Foundation

enum CaptureStore {
    static let directory: URL = {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "app.globaltrans.ocr/shots", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }()

    static func reset() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func writeJPEG(_ data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(UUID().uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func load(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

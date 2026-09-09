import AppKit
import Foundation
import GlobalTransCore
import Observation

enum AppPhase: Equatable {
    case idle
    case selecting
    case loadingModel
    case recognizing
    case translating
    case ready
    case failed(String)
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var phase: AppPhase = .idle
    var captures: [CaptureItem] = []
    var selectedID: UUID?
    var modelLoaded = false
    var keepWarmSeconds: Double = 180
    var hidePanelOnCapture: Bool = true {
        didSet {
            UserDefaults.standard.set(hidePanelOnCapture, forKey: Self.hidePanelOnCaptureKey)
        }
    }
    var remote: RemoteAPISettings = RemoteAPIStore.load() {
        didSet {
            RemoteAPIStore.save(remote)
        }
    }
    var localModelRevision = 0

    var useRemoteOCR: Bool {
        get { remote.useRemoteOCR }
        set {
            guard remote.useRemoteOCR != newValue else { return }
            var next = remote
            next.useRemoteOCR = newValue
            remote = next
            Task { await unloadOCREngine() }
        }
    }

    var useRemoteTranslate: Bool {
        get { remote.useRemoteTranslate }
        set {
            guard remote.useRemoteTranslate != newValue else { return }
            var next = remote
            next.useRemoteTranslate = newValue
            remote = next
            Task { await unloadTranslator() }
        }
    }

    var ocrSourceLabel: String {
        _ = localModelRevision
        if useRemoteOCR {
            let name = remote.ocrModel.isEmpty ? "auto" : remote.ocrModel
            return "\(remote.displayHost) · \(name)"
        }
        return ModelLocator.ocrDisplayPath()
    }

    var translateSourceLabel: String {
        _ = localModelRevision
        if useRemoteTranslate {
            let name = remote.translateModel.isEmpty ? "auto" : remote.translateModel
            return "\(remote.displayHost) · \(name)"
        }
        return ModelLocator.translationDisplayPath()
    }

    private let engine = OCREngine()
    private let translator = TranslationEngine()
    private let overlay = RegionOverlayController()
    private var unloadTask: Task<Void, Never>?
    private var jobIndex = 0
    private var jobTotal = 0

    private static let hidePanelOnCaptureKey = "GTHidePanelOnCapture"

    private init() {
        if UserDefaults.standard.object(forKey: Self.hidePanelOnCaptureKey) != nil {
            hidePanelOnCapture = UserDefaults.standard.bool(forKey: Self.hidePanelOnCaptureKey)
        }
    }

    var selectedCapture: CaptureItem? {
        if let selectedID, let item = captures.first(where: { $0.id == selectedID }) {
            return item
        }
        return captures.last
    }

    var originalText: String {
        guard let item = selectedCapture else { return "" }
        if case .ocrFailed(let message) = item.stage { return message }
        return item.ocrText
    }

    var translatedText: String {
        guard let item = selectedCapture else { return "" }
        if case .translateFailed(let message) = item.stage { return message }
        return item.translatedText
    }

    var pendingOCRCount: Int { captures.filter { $0.stage.needsOCR }.count }
    var pendingTranslateCount: Int { captures.filter { $0.stage.needsTranslate }.count }
    var cacheIsFull: Bool { captures.count >= CaptureItem.cacheLimit }

    var isBusy: Bool {
        switch phase {
        case .selecting, .loadingModel, .recognizing, .translating: return true
        default: return false
        }
    }

    var canAddCapture: Bool { !cacheIsFull && phase != .selecting }
    var canRunOCR: Bool { pendingOCRCount > 0 && !isBusy }
    var canRunTranslate: Bool { pendingTranslateCount > 0 && !isBusy }

    var statusLabel: String {
        switch phase {
        case .idle, .ready:
            if captures.isEmpty {
                return modelLoaded ? "Ready (model warm)" : "Idle"
            }
            if pendingOCRCount > 0 {
                return "\(captures.count)/\(CaptureItem.cacheLimit) cached · \(pendingOCRCount) to OCR"
            }
            if pendingTranslateCount > 0 {
                return "\(captures.count)/\(CaptureItem.cacheLimit) cached · \(pendingTranslateCount) to translate"
            }
            return "\(captures.count)/\(CaptureItem.cacheLimit) cached"
        case .selecting: return "Select a region…"
        case .loadingModel: return "Loading local model…"
        case .recognizing: return "OCR \(jobIndex)/\(jobTotal)…"
        case .translating: return "Translate \(jobIndex)/\(jobTotal)…"
        case .failed(let message): return message
        }
    }

    var iconName: String {
        switch phase {
        case .idle, .ready: return "doc.text.viewfinder"
        case .selecting: return "plus.viewfinder"
        case .loadingModel, .recognizing, .translating: return "hourglass"
        case .failed: return "exclamationmark.triangle"
        }
    }

    func selectCapture(_ id: UUID) {
        selectedID = id
    }

    func removeCapture(_ id: UUID) {
        captures.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = captures.last?.id
        }
        if !isBusy {
            phase = captures.isEmpty ? .idle : .ready
        }
    }

    func captureRegion() async {
        guard canAddCapture else {
            if cacheIsFull {
                phase = .failed("Screenshot cache is full (\(CaptureItem.cacheLimit)). Remove one first.")
            }
            return
        }
        phase = .selecting
        let hidePanel = hidePanelOnCapture
        if hidePanel {
            await StatusPanelHider.hide()
        }
        guard let rect = await overlay.selectRegion() else {
            if hidePanel { StatusPanelHider.restore() }
            phase = captures.isEmpty ? .idle : .ready
            return
        }
        do {
            let cgImage = try await ScreenGrabber.capture(rectInScreen: rect)
            if hidePanel { StatusPanelHider.restore() }
            enqueue(CIImage(cgImage: cgImage), kind: .screen, maxTokens: 2048, maxPixels: 1_638_400)
        } catch {
            if hidePanel { StatusPanelHider.restore() }
            phase = .failed(error.localizedDescription)
        }
    }

    func importFile(url: URL) async {
        guard canAddCapture else {
            if cacheIsFull {
                phase = .failed("Screenshot cache is full (\(CaptureItem.cacheLimit)). Remove one first.")
            }
            return
        }
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            let image = try DocumentImporter.loadCIImage(from: url)
            enqueue(image, kind: .file, maxTokens: 4096, maxPixels: 2_985_984)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func runOCR() async {
        guard canRunOCR else { return }
        cancelUnload()
        let jobs = captures.filter { $0.stage.needsOCR }
        jobTotal = jobs.count
        jobIndex = 0
        do {
            try await prepareOCR()
            for job in jobs {
                jobIndex += 1
                guard captures.contains(where: { $0.id == job.id }) else { continue }
                await ocrItem(job)
            }
            await refreshLoadedFlag()
            phase = .ready
            if modelLoaded { scheduleUnload() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func runTranslate() async {
        guard canRunTranslate else { return }
        cancelUnload()
        let jobs = captures.filter { $0.stage.needsTranslate }
        jobTotal = jobs.count
        jobIndex = 0
        do {
            try await prepareTranslate()
            for job in jobs {
                jobIndex += 1
                guard captures.contains(where: { $0.id == job.id }) else { continue }
                await translateItem(job)
            }
            await refreshLoadedFlag()
            phase = .ready
            if modelLoaded { scheduleUnload() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func copyOriginal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(originalText, forType: .string)
    }

    func copyTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }

    func chooseOCRFolder() -> String {
        chooseFolder(
            message: "Choose the OCR model folder (or its parent).",
            start: (try? ModelLocator.modelDirectory()) ?? ModelLocator.url(fromPath: ocrPathDraftFallback)
        ) { url in
            applyOCRPath(url.path)
        }
    }

    func chooseTranslationFolder() -> String {
        chooseFolder(
            message: "Choose the translation model folder (or its parent).",
            start: (try? ModelLocator.translationDirectory())
                ?? ModelLocator.url(fromPath: translatePathDraftFallback)
        ) { url in
            applyTranslationPath(url.path)
        }
    }

    func applyOCRPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ModelLocator.clearSavedModelDirectory()
            localModelRevision += 1
            Task { await unloadOCREngine() }
            if let url = try? ModelLocator.modelDirectory() {
                return "OK · auto \(ModelLocator.abbreviated(url.path))"
            }
            return "No OCR model found. Paste a folder path, or put OvisOCR2-4bit next to GlobalTrans.app."
        }
        let url = ModelLocator.url(fromPath: trimmed)
        guard let modelURL = ModelLocator.resolveOCRDirectory(url) else {
            return "That folder is not an OCR model (need config.json and model.safetensors)."
        }
        ModelLocator.setSavedModelDirectory(modelURL)
        localModelRevision += 1
        Task { await unloadOCREngine() }
        return "OK · \(ModelLocator.abbreviated(modelURL.path))"
    }

    func applyTranslationPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ModelLocator.clearSavedTranslationDirectory()
            localModelRevision += 1
            Task { await unloadTranslator() }
            if let url = try? ModelLocator.translationDirectory() {
                return "OK · auto \(ModelLocator.abbreviated(url.path))"
            }
            return "No translation model found. Paste a folder path, or put Hy-MT2-1.8B-4bit next to GlobalTrans.app."
        }
        let url = ModelLocator.url(fromPath: trimmed)
        guard let modelURL = ModelLocator.resolveTranslationDirectory(url) else {
            return "That folder is not a translation model (need config.json and model.safetensors)."
        }
        ModelLocator.setSavedTranslationDirectory(modelURL)
        localModelRevision += 1
        Task { await unloadTranslator() }
        return "OK · \(ModelLocator.abbreviated(modelURL.path))"
    }

    private var ocrPathDraftFallback: String {
        ModelLocator.savedOCRPath().isEmpty ? ModelLocator.configuredOCRPath() : ModelLocator.savedOCRPath()
    }

    private var translatePathDraftFallback: String {
        ModelLocator.savedTranslationPath().isEmpty
            ? ModelLocator.configuredTranslationPath() : ModelLocator.savedTranslationPath()
    }

    func unloadNow() async {
        unloadTask?.cancel()
        await engine.unload()
        await translator.unload()
        modelLoaded = false
        if phase == .ready || phase == .idle {
            phase = captures.isEmpty ? .idle : .ready
        }
    }

    private func refreshLoadedFlag() async {
        let ocrLoaded = await engine.isLoaded
        let mtLoaded = await translator.isLoaded
        modelLoaded = ocrLoaded || mtLoaded
    }

    private func enqueue(_ image: CIImage, kind: CaptureKind, maxTokens: Int, maxPixels: Int) {
        guard captures.count < CaptureItem.cacheLimit else {
            phase = .failed("Screenshot cache is full (\(CaptureItem.cacheLimit)). Remove one first.")
            return
        }
        let item = CaptureItem.make(
            image: image,
            kind: kind,
            maxTokens: maxTokens,
            maxPixels: maxPixels
        )
        captures.append(item)
        selectedID = item.id
        phase = .ready
    }

    private func prepareOCR() async throws {
        if await translator.isLoaded {
            await translator.unload()
            modelLoaded = false
        }
        if remote.useRemoteOCR {
            phase = .recognizing
            return
        }
        if await engine.isLoaded {
            phase = .recognizing
            modelLoaded = true
            return
        }
        phase = .loadingModel
        try await engine.load()
        modelLoaded = true
        phase = .recognizing
        refreshSourceDisplay()
    }

    private func prepareTranslate() async throws {
        if await engine.isLoaded {
            await engine.unload()
            modelLoaded = false
        }
        if remote.useRemoteTranslate {
            phase = .translating
            return
        }
        if await translator.isLoaded {
            phase = .translating
            modelLoaded = true
            return
        }
        phase = .loadingModel
        try await translator.load()
        modelLoaded = true
        phase = .translating
        refreshSourceDisplay()
    }

    private func ocrItem(_ item: CaptureItem) async {
        updateCapture(item.id) { $0.stage = .recognizing }
        let request = OCRRequest(
            image: item.image,
            maxTokens: item.maxTokens,
            maxPixels: item.maxPixels
        )
        do {
            let result: OCRResult
            if remote.useRemoteOCR {
                result = try await OpenAICompatibleClient(settings: remote).transcribe(request)
            } else {
                result = try await engine.transcribe(request)
            }
            updateCapture(item.id) { capture in
                capture.ocrText = result.text
                capture.translatedText = ""
                capture.stage = .ocrReady
            }
        } catch {
            updateCapture(item.id) { $0.stage = .ocrFailed(error.localizedDescription) }
        }
    }

    private func translateItem(_ item: CaptureItem) async {
        let text = captures.first(where: { $0.id == item.id })?.ocrText ?? item.ocrText
        guard !text.isEmpty else {
            updateCapture(item.id) { $0.stage = .translateFailed("No OCR text to translate.") }
            return
        }
        updateCapture(item.id) { $0.stage = .translating }
        let chineseSource = LanguageGuess.detect(text) == .chinese
        let request = TranslateRequest(
            text: text,
            chineseSource: chineseSource,
            maxTokens: min(4096, max(384, text.count * 2))
        )
        do {
            let result: OCRResult
            if remote.useRemoteTranslate {
                result = try await OpenAICompatibleClient(settings: remote).translate(request)
            } else {
                result = try await translator.translate(request)
            }
            updateCapture(item.id) { capture in
                capture.translatedText = result.text
                capture.stage = .translated
            }
        } catch {
            updateCapture(item.id) { $0.stage = .translateFailed(error.localizedDescription) }
        }
    }

    private func chooseFolder(
        message: String,
        start: URL?,
        apply: (URL) -> String
    ) -> String {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.directoryURL = start
        guard panel.runModal() == .OK, let url = panel.url else { return "" }
        return apply(url)
    }

    private func unloadOCREngine() async {
        await engine.unload()
        await refreshLoadedFlag()
    }

    private func unloadTranslator() async {
        await translator.unload()
        await refreshLoadedFlag()
    }

    private func refreshSourceDisplay() {
        localModelRevision += 1
    }

    private func updateCapture(_ id: UUID, _ body: (inout CaptureItem) -> Void) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        body(&captures[index])
    }

    private func scheduleUnload() {
        cancelUnload()
        let seconds = keepWarmSeconds
        guard seconds > 0 else {
            Task { await unloadNow() }
            return
        }
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.unloadNow()
        }
    }

    private func cancelUnload() {
        unloadTask?.cancel()
        unloadTask = nil
    }
}

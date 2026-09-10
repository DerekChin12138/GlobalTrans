import AppKit
import Foundation
import GlobalTransCore
import Observation
import os
import UniformTypeIdentifiers

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
    var targetLanguage: TranslateLanguage = .auto {
        didSet {
            UserDefaults.standard.set(targetLanguage.rawValue, forKey: Self.targetLanguageKey)
        }
    }
    var ocrInputPercent: Double = OCRInputSettings.defaultPercent {
        didSet {
            let clamped = OCRInputSettings.clampedPercent(ocrInputPercent)
            if clamped != ocrInputPercent {
                ocrInputPercent = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Self.ocrInputPercentKey)
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
    private let textDraftID = UUID()

    private static let hidePanelOnCaptureKey = "GTHidePanelOnCapture"
    private static let targetLanguageKey = "GTTranslateTargetLang"
    private static let ocrInputPercentKey = "GTOcrInputPercent"
    private static let memoryLog = Logger(subsystem: "app.globaltrans.ocr", category: "memory")

    private init() {
        if UserDefaults.standard.object(forKey: Self.hidePanelOnCaptureKey) != nil {
            hidePanelOnCapture = UserDefaults.standard.bool(forKey: Self.hidePanelOnCaptureKey)
        }
        if let raw = UserDefaults.standard.string(forKey: Self.targetLanguageKey),
           let language = TranslateLanguage(rawValue: raw) {
            targetLanguage = language
        }
        if UserDefaults.standard.object(forKey: Self.ocrInputPercentKey) != nil {
            ocrInputPercent = OCRInputSettings.clampedPercent(
                UserDefaults.standard.double(forKey: Self.ocrInputPercentKey)
            )
        }
        CaptureStore.reset()
    }

    var selectedCapture: CaptureItem? {
        if let selectedID, let item = captures.first(where: { $0.id == selectedID }) {
            return item
        }
        return captures.last
    }

    var originalText: String {
        guard let item = selectedCapture else { return "" }
        if case .ocrFailed(let message) = item.stage,
           item.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return message
        }
        return item.ocrText
    }

    var translatedText: String {
        guard let item = selectedCapture else { return "" }
        if case .translateFailed(let message) = item.stage { return message }
        return item.translatedText
    }

    var pendingOCRCount: Int {
        captures.filter { $0.stage.needsOCR && $0.jpegURL != nil }.count
    }
    var pendingTranslateCount: Int { captures.filter { $0.needsTranslate(to: targetLanguage) }.count }
    var cacheIsFull: Bool { captures.count >= CaptureItem.cacheLimit }

    var isBusy: Bool {
        switch phase {
        case .selecting, .loadingModel, .recognizing, .translating: return true
        default: return false
        }
    }

    var canAddCapture: Bool { !cacheIsFull && phase != .selecting }
    var canRunOCR: Bool {
        guard !isBusy, let item = selectedCapture else { return false }
        return item.jpegURL != nil
    }
    var canRunTranslate: Bool {
        selectedCapture?.needsTranslate(to: targetLanguage) == true && !isBusy
    }
    var canRunAllOCR: Bool { pendingOCRCount > 1 && !isBusy }
    var canRunAllTranslate: Bool { pendingTranslateCount > 1 && !isBusy }
    var canEditOCR: Bool { !isBusy }
    var canOpenMerge: Bool { !isBusy && !captures.isEmpty }
    var editorDocumentID: UUID { selectedCapture?.id ?? textDraftID }
    var editableOCRText: String { selectedCapture?.ocrText ?? "" }
    var ocrPixelBudget: Int { OCRInputSettings.pixels(percent: ocrInputPercent) }

    var mergeDraft = ""
    var mergeTranslation = ""
    var memoryLabel = MLXRuntime.probe().description

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

    func beginTextDraft() {
        guard !isBusy else { return }
        if let existing = captures.first(where: { $0.kind == .text && $0.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            selectedID = existing.id
            return
        }
        guard canAddCapture else { return }
        enqueue(CaptureItem.makeText())
    }

    func removeCapture(_ id: UUID) {
        if let index = captures.firstIndex(where: { $0.id == id }) {
            captures[index].discardPixels()
            captures.remove(at: index)
        }
        if selectedID == id {
            selectedID = captures.last?.id
        }
        if !isBusy {
            phase = captures.isEmpty ? .idle : .ready
        }
        purgeDiscardedMedia()
        if captures.isEmpty, !isBusy {
            Task { await unloadNow() }
        } else {
            refreshMemory()
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
            refreshMemory()
            return
        }
        do {
            let item = try await ScreenGrabber.captureItem(rectInScreen: rect)
            if hidePanel { StatusPanelHider.restore() }
            enqueue(item)
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
            let item = try autoreleasepool {
                try DocumentImporter.makeCaptureItem(from: url)
            }
            enqueue(item)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func importFromOpenPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.setActivationPolicy(.regular)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .pdf, .image]
        panel.message = "Choose an image or PDF to OCR"
        ChildWindow.focus(panel)
        let response = panel.runModal()
        let pickedURL = panel.url
        panel.close()
        panel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        StatusItemContextMenu.presentMainPanel()
        guard response == .OK, let url = pickedURL else { return }
        Task { await importFile(url: url) }
    }

    func runOCR(onlySelected: Bool = true) async {
        guard onlySelected ? canRunOCR : (pendingOCRCount > 0 && !isBusy) else { return }
        cancelUnload()
        let jobIDs: [UUID]
        if onlySelected, let item = selectedCapture, item.jpegURL != nil {
            jobIDs = [item.id]
        } else {
            jobIDs = captures.filter { $0.stage.needsOCR && $0.jpegURL != nil }.map(\.id)
        }
        guard !jobIDs.isEmpty else { return }
        jobTotal = jobIDs.count
        jobIndex = 0
        do {
            try await prepareOCR()
            for id in jobIDs {
                jobIndex += 1
                guard captures.contains(where: { $0.id == id }) else { continue }
                await ocrItem(id)
            }
            await refreshLoadedFlag()
            phase = .ready
            if modelLoaded { scheduleUnload() }
            refreshMemory()
        } catch {
            phase = .failed(error.localizedDescription)
            refreshMemory()
        }
    }

    func runTranslate(onlySelected: Bool = true) async {
        guard onlySelected ? canRunTranslate : (pendingTranslateCount > 0 && !isBusy) else { return }
        cancelUnload()
        let jobIDs: [UUID]
        if onlySelected, let item = selectedCapture, item.needsTranslate(to: targetLanguage) {
            jobIDs = [item.id]
        } else {
            jobIDs = captures.filter { $0.needsTranslate(to: targetLanguage) }.map(\.id)
        }
        guard !jobIDs.isEmpty else { return }
        jobTotal = jobIDs.count
        jobIndex = 0
        do {
            try await prepareTranslate()
            for id in jobIDs {
                jobIndex += 1
                guard captures.contains(where: { $0.id == id }) else { continue }
                await translateItem(id)
            }
            await translator.unload()
            await refreshLoadedFlag()
            phase = .ready
            refreshMemory()
        } catch {
            await translator.unload()
            await refreshLoadedFlag()
            phase = .failed(error.localizedDescription)
            refreshMemory()
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

    func setOCRText(_ text: String, for id: UUID? = nil) {
        guard !isBusy else { return }
        let target = resolveEditableCaptureID(id, initialText: text)
        updateCapture(target) { capture in
            guard capture.ocrText != text else { return }
            capture.ocrText = text
            capture.translatedText = ""
            capture.translatedTarget = nil
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if capture.stage != .queued && capture.stage != .recognizing {
                    capture.stage = .queued
                }
            } else {
                capture.stage = .ocrReady
            }
        }
    }

    private func resolveEditableCaptureID(_ id: UUID?, initialText: String) -> UUID {
        if let id, captures.contains(where: { $0.id == id }) {
            return id
        }
        if let selected = selectedCapture {
            return selected.id
        }
        if !captures.contains(where: { $0.id == textDraftID }),
           captures.count < CaptureItem.cacheLimit
        {
            var item = CaptureItem.makeText(id: textDraftID)
            item.ocrText = initialText
            if !initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                item.stage = .ocrReady
            }
            captures.append(item)
            selectedID = textDraftID
            if phase == .idle { phase = .ready }
            return textDraftID
        }
        return selectedCapture?.id ?? textDraftID
    }

    func prepareMergeWorkspace() {
        if mergeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mergeDraft = joinedOCRTexts()
        }
    }

    func resetMergeDraft() {
        mergeDraft = joinedOCRTexts()
        mergeTranslation = ""
    }

    func insertOCRIntoMerge(_ id: UUID) {
        guard let text = captures.first(where: { $0.id == id })?.ocrText
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return }
        if mergeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mergeDraft = text
        } else {
            mergeDraft += "\n\n" + text
        }
    }

    func copyMergeDraft() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mergeDraft, forType: .string)
    }

    func copyMergeTranslation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mergeTranslation, forType: .string)
    }

    func translateMergeDraft() async {
        let text = mergeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        cancelUnload()
        do {
            try await prepareTranslate()
            let request = TranslateRequest(
                text: text,
                sourceLanguage: .auto,
                targetLanguage: targetLanguage,
                maxTokens: min(4096, max(384, text.count * 2))
            )
            let result: OCRResult
            if remote.useRemoteTranslate {
                result = try await OpenAICompatibleClient(settings: remote).translate(request)
            } else {
                result = try await translator.translate(request)
            }
            mergeTranslation = result.text
            await translator.unload()
            await refreshLoadedFlag()
            phase = captures.isEmpty ? .idle : .ready
            refreshMemory()
        } catch {
            mergeTranslation = error.localizedDescription
            await translator.unload()
            await refreshLoadedFlag()
            phase = captures.isEmpty ? .idle : .ready
            refreshMemory()
        }
    }

    private func joinedOCRTexts() -> String {
        captures
            .map { $0.ocrText.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
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
        refreshMemory()
    }

    private func refreshLoadedFlag() async {
        let ocrLoaded = await engine.isLoaded
        let mtLoaded = await translator.isLoaded
        modelLoaded = ocrLoaded || mtLoaded
    }

    private func enqueue(_ item: CaptureItem) {
        guard captures.count < CaptureItem.cacheLimit else {
            phase = .failed("Screenshot cache is full (\(CaptureItem.cacheLimit)). Remove one first.")
            return
        }
        captures.append(item)
        selectedID = item.id
        phase = .ready
        refreshMemory()
    }

    private func purgeDiscardedMedia() {
        ImageResizer.clearCaches()
        if captures.isEmpty {
            mergeDraft = ""
            mergeTranslation = ""
        }
        if !isBusy {
            MLXRuntime.releaseAll()
        }
    }

    func refreshMemory() {
        let snapshot = MLXRuntime.probe()
        memoryLabel = snapshot.description
        Self.memoryLog.info("\(snapshot.description, privacy: .public)")
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

    private func ocrItem(_ id: UUID) async {
        updateCapture(id) { $0.stage = .recognizing }
        let result: OCRResult
        do {
            guard let jpeg = captures.first(where: { $0.id == id })?.jpegData(), !jpeg.isEmpty
            else {
                updateCapture(id) { $0.stage = .ocrFailed("Screenshot data is missing.") }
                return
            }
            let request = OCRRequest(
                jpeg: jpeg,
                maxTokens: OCRInputSettings.maxTokens(percent: ocrInputPercent),
                maxPixels: ocrPixelBudget
            )
            if remote.useRemoteOCR {
                result = try await OpenAICompatibleClient(settings: remote).transcribe(request)
            } else {
                result = try await engine.transcribe(request)
            }
        } catch {
            updateCapture(id) { $0.stage = .ocrFailed(error.localizedDescription) }
            return
        }
        updateCapture(id) { capture in
            capture.ocrText = result.text
            capture.translatedText = ""
            capture.translatedTarget = nil
            capture.discardPixels()
            capture.stage = .ocrReady
        }
        ImageResizer.clearCaches()
        refreshMemory()
    }

    private func translateItem(_ id: UUID) async {
        let text = captures.first(where: { $0.id == id })?.ocrText ?? ""
        guard !text.isEmpty else {
            updateCapture(id) { $0.stage = .translateFailed("Nothing to translate. Type in the OCR box or run OCR first.") }
            return
        }
        updateCapture(id) { $0.stage = .translating }
        let request = TranslateRequest(
            text: text,
            sourceLanguage: .auto,
            targetLanguage: targetLanguage,
            maxTokens: min(4096, max(384, text.count * 2))
        )
        do {
            let result: OCRResult
            if remote.useRemoteTranslate {
                result = try await OpenAICompatibleClient(settings: remote).translate(request)
            } else {
                result = try await translator.translate(request)
            }
            let target = targetLanguage
            updateCapture(id) { capture in
                capture.translatedText = result.text
                capture.translatedTarget = target
                capture.stage = .translated
            }
        } catch {
            updateCapture(id) { $0.stage = .translateFailed(error.localizedDescription) }
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
        ChildWindow.focus(panel)
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

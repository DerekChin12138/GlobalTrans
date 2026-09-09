import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatusPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var importerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.iconName)
                Text(model.statusLabel)
                    .font(.headline)
                Spacer()
            }

            sourceSwitch(
                title: "OCR",
                isRemote: $model.useRemoteOCR,
                path: model.ocrSourceLabel
            )
            sourceSwitch(
                title: "Translate",
                isRemote: $model.useRemoteTranslate,
                path: model.translateSourceLabel
            )

            HStack(spacing: 8) {
                Button("Capture") {
                    Task { await model.captureRegion() }
                }
                .disabled(!model.canAddCapture)

                Button("Open File…") {
                    importerPresented = true
                }
                .disabled(!model.canAddCapture)

                Button("Unload Model") {
                    Task { await model.unloadNow() }
                }
                .disabled(!model.modelLoaded)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Button(model.pendingOCRCount > 0 ? "OCR (\(model.pendingOCRCount))" : "OCR") {
                    Task { await model.runOCR() }
                }
                .disabled(!model.canRunOCR)

                Button(model.pendingTranslateCount > 0 ? "Translate (\(model.pendingTranslateCount))" : "Translate") {
                    Task { await model.runTranslate() }
                }
                .disabled(!model.canRunTranslate)

                Spacer()
            }
            .controlSize(.small)

            CaptureStrip(model: model)

            Group {
                labeledEditor(title: "OCR", text: model.originalText, copy: model.copyOriginal)
                labeledEditor(title: "Translation", text: model.translatedText, copy: model.copyTranslation)
            }

            if case .failed = model.phase {
                Button("Open Screen Recording Settings") {
                    ScreenAccess.openSettings()
                }
                .controlSize(.small)
            }

            HStack {
                Toggle("Hide window while capturing", isOn: $model.hidePanelOnCapture)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Models…") {
                    openWindow(id: "models")
                }
                .controlSize(.small)
            }

            Text("Hotkey: ⌥⌘O caches a screenshot · OCR and Translate are manual")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 420, height: 600)
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: [.pdf, .png, .jpeg, .heic, .tiff, .image]
        ) { result in
            if case .success(let url) = result {
                Task { await model.importFile(url: url) }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.canAddCapture, let url = urls.first else { return false }
            Task { await model.importFile(url: url) }
            return true
        }
    }

    private func labeledEditor(title: String, text: String, copy: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy", action: copy)
                    .controlSize(.mini)
                    .disabled(text.isEmpty)
            }
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 88)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func sourceSwitch(title: String, isRemote: Binding<Bool>, path: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .frame(width: 62, alignment: .leading)
                Text("Local")
                    .font(.caption2)
                    .foregroundStyle(isRemote.wrappedValue ? .secondary : .primary)
                Toggle("Remote", isOn: isRemote)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(model.isBusy)
                Text("Remote")
                    .font(.caption2)
                    .foregroundStyle(isRemote.wrappedValue ? .primary : .secondary)
                Spacer()
            }
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
        }
    }
}

private struct CaptureStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cache \(model.captures.count)/\(CaptureItem.cacheLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(model.captures) { item in
                    CaptureThumb(
                        item: item,
                        selected: item.id == model.selectedCapture?.id,
                        onSelect: { model.selectCapture(item.id) },
                        onRemove: { model.removeCapture(item.id) }
                    )
                }
                ForEach(0..<emptySlotCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(width: 64, height: 52)
                }
            }
        }
    }

    private var emptySlotCount: Int {
        max(0, CaptureItem.cacheLimit - model.captures.count)
    }
}

private struct CaptureThumb: View {
    let item: CaptureItem
    let selected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                Image(nsImage: item.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 52)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        Text(item.stage.badge)
                            .font(.system(size: 8, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 2)
                    }
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .offset(x: 3, y: -3)
        }
        .frame(width: 64, height: 52)
        .help(item.stage.badge)
    }
}

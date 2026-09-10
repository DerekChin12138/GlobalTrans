import AppKit
import GlobalTransCore
import SwiftUI

struct StatusPanel: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.iconName)
                Text(model.statusLabel)
                    .font(.headline)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
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
                    model.importFromOpenPanel()
                }
                .disabled(!model.canAddCapture)

                Button("Unload Model") {
                    Task { await model.unloadNow() }
                }
                .disabled(!model.modelLoaded)

                Spacer()
            }
            .controlSize(.small)

            if model.pendingOCRCount > 1 || model.pendingTranslateCount > 1 {
                HStack(spacing: 8) {
                    if model.pendingOCRCount > 1 {
                        Button("OCR All (\(model.pendingOCRCount))") {
                            Task { await model.runOCR(onlySelected: false) }
                        }
                        .disabled(!model.canRunAllOCR)
                    }

                    if model.pendingTranslateCount > 1 {
                        Button("Translate All (\(model.pendingTranslateCount))") {
                            Task { await model.runTranslate(onlySelected: false) }
                        }
                        .disabled(!model.canRunAllTranslate)
                    }

                    Spacer()
                }
                .controlSize(.small)
            }

            CaptureStrip(model: model)

            HStack(spacing: 6) {
                Text("Translate to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Translate to", selection: $model.targetLanguage) {
                    ForEach(TranslateLanguage.allCases) { language in
                        Text(language.menuLabel).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .disabled(model.isBusy)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("OCR input")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((model.ocrInputPercent * 100).rounded()))% · \(OCRInputSettings.megapixelsLabel(model.ocrPixelBudget)) / \(OCRInputSettings.megapixelsLabel(OCRInputSettings.officialMaxPixels))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: $model.ocrInputPercent,
                    in: OCRInputSettings.minPercent...OCRInputSettings.maxPercent,
                    step: 0.05
                )
                .controlSize(.mini)
                .disabled(model.isBusy)
                .help("100% is OvisOCR2’s official max of 2880×2880 pixels. Images larger than the budget are downscaled before OCR.")
            }

            VStack(spacing: 10) {
                ResultPane(
                    title: "OCR",
                    text: model.originalText,
                    copy: model.copyOriginal,
                    popOut: { openPreview(.ocr) },
                    compact: true,
                    documentID: model.editorDocumentID,
                    editText: model.editableOCRText,
                    onEdit: model.canEditOCR ? { model.setOCRText($0) } : nil,
                    actionTitle: "OCR",
                    actionEnabled: model.canRunOCR,
                    actionHelp: "OCR the selected screenshot",
                    action: {
                        Task { await model.runOCR(onlySelected: true) }
                    }
                )
                ResultPane(
                    title: "Translation",
                    text: model.translatedText,
                    copy: model.copyTranslation,
                    popOut: { openPreview(.translation) },
                    documentID: model.editorDocumentID,
                    actionTitle: "Translate",
                    actionEnabled: model.canRunTranslate,
                    actionHelp: "Translate the OCR box text, typed or recognized",
                    action: {
                        Task { await model.runTranslate(onlySelected: true) }
                    }
                )
            }
            .layoutPriority(1)

            Button {
                model.prepareMergeWorkspace()
                openWindow(id: "ocr-merge")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("Merge some contexts")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .disabled(!model.canOpenMerge)
            .help("Combine texts from cached screenshots in a new window")

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
                    NSApp.activate(ignoringOtherApps: true)
                }
                .controlSize(.small)
            }

            Text("Hotkey: ⌥⌘O caches a screenshot · or type in the OCR box to translate")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(model.memoryLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .help("phys_footprint · IOSurface/external · MLX active+cache")
        }
        .padding(14)
        .frame(width: 420, height: 748)
        .background(StatusPanelWindowMarker())
        .onAppear {
            StatusItemContextMenu.install()
            model.refreshMemory()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard model.canAddCapture, let url = urls.first else { return false }
            Task { await model.importFile(url: url) }
            return true
        }
    }

    private func openPreview(_ kind: PreviewWindowID) {
        openWindow(id: "preview", value: kind)
        NSApp.activate(ignoringOtherApps: true)
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
                ForEach(Array(model.captures.enumerated()), id: \.element.id) { index, item in
                    CaptureThumb(
                        thumbnail: item.thumbnailImage,
                        index: index + 1,
                        badge: item.displayBadge,
                        selected: item.id == model.selectedID,
                        onSelect: { model.selectCapture(item.id) },
                        onRemove: { model.removeCapture(item.id) }
                    )
                }
                ForEach(0..<emptySlotCount, id: \.self) { _ in
                    Button {
                        model.beginTextDraft()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 64, height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isBusy)
                    .help("New text · click to type and translate")
                }
            }
        }
    }

    private var emptySlotCount: Int {
        max(0, CaptureItem.cacheLimit - model.captures.count)
    }
}

private struct CaptureThumb: View {
    let thumbnail: NSImage
    let index: Int
    let badge: String
    let selected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 52)
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    Text("\(index)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(3)
                }
                .overlay(alignment: .bottom) {
                    Text(badge)
                        .font(.system(size: 8, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
                )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .offset(x: 2, y: -2)
            .zIndex(2)
        }
        .frame(width: 64, height: 52)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .help("Screenshot \(index) · \(badge)")
    }
}

private struct StatusPanelWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ nsView: MarkerView, context: Context) {}

    final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(StatusPanelHider.panelWindowID)
            window.styleMask.remove(.resizable)
        }
    }
}

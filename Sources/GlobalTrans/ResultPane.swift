import MarkdownUI
import SwiftUI

enum PreviewWindowID: String, Codable, Hashable {
    case ocr
    case translation

    var title: String {
        switch self {
        case .ocr: return "OCR"
        case .translation: return "Translation"
        }
    }
}

private enum ResultPaneMode: String, CaseIterable, Identifiable {
    case preview
    case raw
    case edit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: return "Preview"
        case .raw: return "Raw"
        case .edit: return "Edit"
        }
    }
}

struct ResultPane: View {
    let title: String
    let text: String
    let copy: () -> Void
    var popOut: (() -> Void)? = nil
    var compact: Bool = true
    var documentID: UUID? = nil
    var editText: String? = nil
    var onEdit: ((String) -> Void)? = nil
    var actionTitle: String? = nil
    var actionEnabled: Bool = true
    var actionHelp: String? = nil
    var action: (() -> Void)? = nil
    @State private var mode: ResultPaneMode = .preview
    @Environment(\.colorScheme) private var colorScheme

    private var isEditable: Bool { onEdit != nil }
    private var modes: [ResultPaneMode] { isEditable ? [.preview, .edit] : [.preview, .raw] }
    private var editorText: String { editText ?? text }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .font(.body.weight(.semibold))
                        .disabled(!actionEnabled)
                        .help(actionHelp ?? actionTitle)
                } else {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("Mode", selection: $mode) {
                    ForEach(modes) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 128)
                Spacer()
                if let popOut {
                    Button(action: popOut) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .controlSize(.mini)
                    .help("Open in new window")
                    .disabled(text.isEmpty && editorText.isEmpty)
                }
                Button("Copy", action: copy)
                    .controlSize(.mini)
                    .disabled(text.isEmpty)
            }
            Group {
                if isEditable, mode == .edit {
                    TextEditor(
                        text: Binding(
                            get: { editorText },
                            set: { onEdit?($0) }
                        )
                    )
                    .font(.system(size: compact ? 12 : 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .id(documentID)
                } else {
                    ScrollView {
                        Group {
                            if text.isEmpty {
                                Text("—")
                                    .foregroundStyle(.secondary)
                            } else if mode == .raw {
                                Text(text)
                                    .font(.system(compact ? .callout : .body, design: compact ? .default : .monospaced))
                                    .textSelection(.enabled)
                            } else {
                                MixedMarkdownView(
                                    text: text,
                                    compact: compact,
                                    dark: colorScheme == .dark
                                )
                                .equatable()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: compact ? 88 : 280, maxHeight: .infinity)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id(documentID)
    }
}

struct ResultPreviewWindow: View {
    let kind: PreviewWindowID
    @Bindable var model: AppModel

    var body: some View {
        ResultPane(
            title: kind.title,
            text: kind == .ocr ? model.originalText : model.translatedText,
            copy: kind == .ocr ? model.copyOriginal : model.copyTranslation,
            compact: false,
            documentID: model.selectedCapture?.id,
            editText: kind == .ocr ? model.editableOCRText : nil,
            onEdit: kind == .ocr && model.canEditOCR
                ? { text in
                    if let id = model.selectedCapture?.id {
                        model.setOCRText(text, for: id)
                    }
                }
                : nil
        )
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(kind.title)
    }
}

struct MixedMarkdownView: View, Equatable {
    let text: String
    var compact: Bool = true
    var dark: Bool

    private var bodyFontSize: CGFloat { compact ? 13 : 15 }
    private var displayFontSize: CGFloat { compact ? 16 : 18 }

    static func == (lhs: MixedMarkdownView, rhs: MixedMarkdownView) -> Bool {
        lhs.text == rhs.text && lhs.compact == rhs.compact && lhs.dark == rhs.dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            ForEach(
                Array(
                    MarkdownPreviewText.segments(
                        from: text,
                        fontSize: bodyFontSize,
                        dark: dark
                    ).enumerated()
                ),
                id: \.offset
            ) { _, segment in
                switch segment {
                case .markdown(let markdown):
                    Markdown(markdown)
                        .markdownTheme(.basic)
                        .markdownTextStyle {
                            FontSize(bodyFontSize)
                        }
                        .markdownInlineImageProvider(MathInlineImageProvider())
                        .markdownImageProvider(MathBlockImageProvider())
                        .textSelection(.enabled)
                case .displayMath(let latex):
                    MathView(
                        equation: latex,
                        fontSize: displayFontSize,
                        labelMode: .display,
                        textAlignment: .center
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 6 : 10)
                }
            }
        }
    }
}

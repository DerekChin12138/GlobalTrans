import SwiftUI

struct OCRMergeWindow: View {
    @Bindable var model: AppModel
    @State private var draftMode: MergePaneMode = .edit
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HSplitView {
            sourceList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            VStack(alignment: .leading, spacing: 10) {
                Text("Edit the combined OCR text here. Individual screenshots stay unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                draftPane
                translationPane
            }
            .padding(14)
            .frame(minWidth: 480, minHeight: 420)
        }
        .navigationTitle("Merge OCR")
        .background(FrontmostWindow())
        .onAppear {
            model.prepareMergeWorkspace()
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    model.resetMergeDraft()
                }
                .controlSize(.mini)
                .help("Replace the editor with all current OCR texts")
                .disabled(model.isBusy)
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)

            List(model.captures) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(nsImage: item.thumbnailImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 36)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.stage.badge)
                                .font(.caption2.weight(.semibold))
                            Text(preview(for: item))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Button("Insert") {
                        model.insertOCRIntoMerge(item.id)
                    }
                    .controlSize(.mini)
                    .disabled(
                        item.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || model.isBusy
                    )
                }
                .padding(.vertical, 4)
            }
        }
        .background(.background)
    }

    private var draftPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Merged OCR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: $draftMode) {
                    ForEach(MergePaneMode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)
                .frame(width: 128)
                Spacer()
                Button("Copy") {
                    model.copyMergeDraft()
                }
                .controlSize(.mini)
                .disabled(model.mergeDraft.isEmpty)
                Button("Translate") {
                    Task { await model.translateMergeDraft() }
                }
                .controlSize(.mini)
                .disabled(
                    model.mergeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || model.isBusy
                )
            }
            Group {
                if draftMode == .edit {
                    TextEditor(text: $model.mergeDraft)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                } else if model.mergeDraft.isEmpty {
                    Text("—")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        MixedMarkdownView(
                            text: model.mergeDraft,
                            compact: false,
                            dark: colorScheme == .dark
                        )
                        .equatable()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(minHeight: 220)
        .layoutPriority(1)
    }

    private var translationPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Translation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    model.copyMergeTranslation()
                }
                .controlSize(.mini)
                .disabled(model.mergeTranslation.isEmpty)
            }
            ScrollView {
                Group {
                    if model.mergeTranslation.isEmpty {
                        Text("—")
                            .foregroundStyle(.secondary)
                    } else {
                        MixedMarkdownView(
                            text: model.mergeTranslation,
                            compact: false,
                            dark: colorScheme == .dark
                        )
                        .equatable()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(minHeight: 160)
    }

    private func preview(for item: CaptureItem) -> String {
        let text = item.ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No OCR yet" : text
    }
}

private enum MergePaneMode: String, CaseIterable, Identifiable {
    case preview
    case edit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preview: return "Preview"
        case .edit: return "Edit"
        }
    }
}

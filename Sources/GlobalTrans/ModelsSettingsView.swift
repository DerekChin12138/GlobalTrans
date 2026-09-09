import GlobalTransCore
import SwiftUI

struct ModelsSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var listedModels: [String] = []
    @State private var message = ""
    @State private var busy = false
    @State private var ocrPath = ""
    @State private var translatePath = ""

    var body: some View {
        let _ = model.localModelRevision
        VStack(alignment: .leading, spacing: 16) {
            Text("Models")
                .font(.title2.weight(.semibold))

            GroupBox("Local") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste a folder path or choose one. On another Mac, copy the model folders next to GlobalTrans.app, or set the paths here. Leave empty and Apply to auto-detect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    pathEditor(
                        title: "OCR folder",
                        path: $ocrPath,
                        placeholder: "~/Applications/OvisOCR2-4bit",
                        apply: { message = model.applyOCRPath(ocrPath) },
                        choose: {
                            let result = model.chooseOCRFolder()
                            if !result.isEmpty { message = result }
                            ocrPath = ModelLocator.configuredOCRPath()
                        }
                    )
                    pathEditor(
                        title: "Translate folder",
                        path: $translatePath,
                        placeholder: "~/Applications/Hy-MT2-1.8B-4bit",
                        apply: { message = model.applyTranslationPath(translatePath) },
                        choose: {
                            let result = model.chooseTranslationFolder()
                            if !result.isEmpty { message = result }
                            translatePath = ModelLocator.configuredTranslationPath()
                        }
                    )
                }
                .padding(6)
            }

            GroupBox("Remote API") {
                VStack(alignment: .leading, spacing: 8) {
                    labeledField("Base URL", text: remoteField(\.baseURL), prompt: RemoteAPIStore.defaultBaseURL)
                    labeledSecure("API key", text: remoteField(\.apiKey))
                    modelChooser(title: "OCR model", selection: remoteField(\.ocrModel))
                    modelChooser(title: "Translate model", selection: remoteField(\.translateModel))

                    if !listedModels.isEmpty {
                        Text("\(listedModels.count) model\(listedModels.count == 1 ? "" : "s") from \(model.remote.displayHost)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("OK") ? .secondary : Color.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(listedModels.isEmpty ? "Load remote models" : "Refresh remote models") {
                    Task { await fetchModels() }
                }
                .disabled(busy)

                Button("Test") {
                    Task { await fetchModels() }
                }
                .disabled(busy)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(20)
        .frame(width: 540)
        .disabled(busy)
        .onAppear(perform: reloadLocalPaths)
        .onChange(of: model.localModelRevision) {
            reloadLocalPaths()
        }
        .task {
            if model.useRemoteOCR || model.useRemoteTranslate {
                await fetchModels()
            }
        }
    }

    private var selectableModels: [String] {
        var ids = listedModels
        for extra in [model.remote.ocrModel, model.remote.translateModel] {
            let trimmed = extra.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !ids.contains(trimmed) {
                ids.insert(trimmed, at: 0)
            }
        }
        return ids
    }

    private func remoteField<T>(_ keyPath: WritableKeyPath<RemoteAPISettings, T>) -> Binding<T> {
        Binding(
            get: { model.remote[keyPath: keyPath] },
            set: { value in
                var next = model.remote
                next[keyPath: keyPath] = value
                model.remote = next
            }
        )
    }

    private func reloadLocalPaths() {
        ocrPath = ModelLocator.configuredOCRPath()
        translatePath = ModelLocator.configuredTranslationPath()
    }

    private func pathEditor(
        title: String,
        path: Binding<String>,
        placeholder: String,
        apply: @escaping () -> Void,
        choose: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(apply)
                Button("Choose…", action: choose)
                    .controlSize(.small)
                Button("Apply", action: apply)
                    .controlSize(.small)
            }
        }
    }

    private func modelChooser(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if listedModels.isEmpty {
                TextField("optional · auto uses the first listed model", text: selection)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                Picker(title, selection: selection) {
                    Text("Auto (first listed)").tag("")
                    ForEach(selectableModels, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private func labeledField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    Task { await fetchModels() }
                }
        }
    }

    private func labeledSecure(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("optional for some local servers", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    Task { await fetchModels() }
                }
        }
    }

    private func fetchModels() async {
        busy = true
        message = ""
        defer { busy = false }
        do {
            let ids = try await OpenAICompatibleClient(settings: model.remote).listModels()
            listedModels = ids
            if ids.isEmpty {
                message = "OK · server reachable, but /v1/models listed nothing. Load a model in LM Studio or enable Just-In-Time loading."
            } else {
                message = "OK · \(ids.count) model\(ids.count == 1 ? "" : "s")"
            }
        } catch {
            listedModels = []
            message = error.localizedDescription
        }
    }
}

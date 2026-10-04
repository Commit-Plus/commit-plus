// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct CustomActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomActionDraft
    @State private var validationMessage: String?

    let onSave: (CustomActionDefinition) -> Void

    init(action: CustomActionDefinition?, onSave: @escaping (CustomActionDefinition) -> Void) {
        _draft = State(initialValue: CustomActionDraft(action: action))
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $draft.name)

                Picker("Type", selection: $draft.sourceKind) {
                    Text("Executable").tag(CustomActionSourceKind.executable)
                    Text("Local Script").tag(CustomActionSourceKind.localScript)
                    Text("Synced Script").tag(CustomActionSourceKind.syncedScript)
                }

                sourceFields

                TextField("Arguments", text: $draft.rawArguments)
                    .font(.body.monospaced())

                VStack(alignment: .leading, spacing: 5) {
                    Text("Placeholders must be standalone arguments.")
                    Text("$REPO — repository path   $FILE — selected file paths   $SHA — selected commit hashes")
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.secondary)

                Section("Availability") {
                    Toggle("Repository", isOn: $draft.repositoryAvailable)
                    Toggle("Selected Files", isOn: $draft.filesAvailable)
                    Toggle("Selected Commits", isOn: $draft.commitsAvailable)
                }

                Toggle("Always Show Output", isOn: $draft.alwaysShowOutput)

                if draft.sourceKind == .syncedScript {
                    Text("The script source, arguments, and executable metadata are stored in your Firebase account when Settings Sync is enabled. Do not include credentials or tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: draft.sourceKind == .syncedScript ? 620 : 470)
    }

    @ViewBuilder
    private var sourceFields: some View {
        switch draft.sourceKind {
        case .executable:
            LabeledContent("Executable") {
                HStack {
                    TextField("/absolute/path/to/executable", text: $draft.executablePath)
                        .font(.body.monospaced())
                    Button("Choose…", action: chooseSource)
                }
            }
        case .localScript:
            LabeledContent("Script") {
                HStack {
                    TextField("/absolute/path/to/script", text: $draft.executablePath)
                        .font(.body.monospaced())
                    Button("Choose…", action: chooseSource)
                }
            }
            scriptLanguagePicker
        case .syncedScript:
            LabeledContent("Imported File") {
                HStack {
                    Text(draft.sourceFileName)
                        .foregroundStyle(.secondary)
                    Button("Import…", action: chooseSource)
                }
            }
            scriptLanguagePicker
            TextEditor(text: $draft.scriptSource)
                .font(.body.monospaced())
                .frame(minHeight: 220)
                .border(.separator)
                .accessibilityLabel("Script source")
        }
    }

    private var scriptLanguagePicker: some View {
        Picker("Language", selection: $draft.scriptLanguage) {
            ForEach(CustomActionScriptLanguage.allCases, id: \.self) { language in
                Text(language.displayName).tag(language)
            }
        }
    }

    private func chooseSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if draft.sourceKind == .syncedScript {
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= CustomActionValidator.maximumScriptBytes,
                      let source = String(data: data, encoding: .utf8) else {
                    throw CustomActionValidationError.scriptTooLarge
                }
                draft.scriptSource = source
                draft.sourceFileName = url.lastPathComponent
                if let language = CustomActionScriptLanguage.inferred(from: url) {
                    draft.scriptLanguage = language
                }
                validationMessage = nil
            } catch {
                validationMessage = error.localizedDescription
            }
        } else {
            draft.executablePath = url.path
            if draft.sourceKind == .localScript,
               let language = CustomActionScriptLanguage.inferred(from: url) {
                draft.scriptLanguage = language
            }
        }
    }

    private func save() {
        do {
            let action = try draft.definition()
            onSave(action)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

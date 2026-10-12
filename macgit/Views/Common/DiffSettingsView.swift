// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct DiffSettingsView: View {
    @Binding var draft: DiffAppearanceSettingsDraft
    @Binding var syntaxHighlighting: Bool
    @State private var showingResetConfirmation = false

    private let fontNames = NSFontManager.shared.availableFonts
        .filter { NSFont(name: $0, size: 12)?.isFixedPitch == true }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(
                    title: "Syntax highlighting",
                    detail: "Color code syntax in diff views. This uses more CPU and memory, especially for large changes.",
                    isOn: $syntaxHighlighting
                )
            } header: {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Section {
                LabeledContent("Font") {
                    Picker("Font", selection: $draft.fontName) {
                        ForEach(fontNames, id: \.self) { fontName in
                            Text(displayName(for: fontName))
                                .font(.custom(fontName, size: 13))
                                .tag(fontName)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                LabeledContent("Size") {
                    HStack {
                        Slider(value: $draft.fontSize, in: 8...32, step: 1)
                            .frame(width: 210)
                        Text("\(Int(draft.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            } header: {
                Label("Diff Font", systemImage: "textformat")
            } footer: {
                Text("Only fixed-width fonts are listed. Diff text size is independent of the app-wide text-size preference.")
            }

            Section {
                LabeledContent("Added line") {
                    HStack(spacing: 14) {
                        colorControl("Background", color: $draft.addedBackgroundColor)
                        colorControl("Text", color: $draft.addedTextColor)
                    }
                }

                LabeledContent("Removed line") {
                    HStack(spacing: 14) {
                        colorControl("Background", color: $draft.removedBackgroundColor)
                        colorControl("Text", color: $draft.removedTextColor)
                    }
                }

                DiffSettingsPreview(draft: draft)
                    .padding(.vertical, 6)
            } header: {
                Label("Diff Colors", systemImage: "paintpalette")
            } footer: {
                Text("Changed-line text colors take priority over syntax highlighting so additions and removals remain easy to distinguish.")
            }

            Section {
            } footer: {
                SettingsActionRow {
                    Button("Restore Diff Defaults…", action: showResetConfirmation)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Diff")
        .confirmationDialog("Restore Diff Defaults?", isPresented: $showingResetConfirmation) {
            Button("Restore Defaults", role: .destructive, action: restoreDefaults)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The diff font and all four diff colors will return to their defaults.")
        }
    }

    private func colorControl(_ title: String, color: Binding<NSColor>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ColorPicker(
                title,
                selection: Binding(
                    get: { Color(nsColor: color.wrappedValue) },
                    set: { color.wrappedValue = NSColor($0) }
                ),
                supportsOpacity: true
            )
                .labelsHidden()
        }
    }

    private func displayName(for fontName: String) -> String {
        NSFont(name: fontName, size: 12)?.displayName ?? fontName
    }

    private func showResetConfirmation() {
        showingResetConfirmation = true
    }

    private func restoreDefaults() {
        draft = DiffAppearanceSettingsStore.defaultDraft
        syntaxHighlighting = false
    }
}

private struct DiffSettingsPreview: View {
    let draft: DiffAppearanceSettingsDraft

    var body: some View {
        VStack(spacing: 0) {
            previewLine(
                prefix: "−", text: "let oldValue = calculate()",
                background: draft.removedBackgroundColor,
                foreground: draft.removedTextColor
            )
            previewLine(
                prefix: "+", text: "let newValue = calculate()",
                background: draft.addedBackgroundColor,
                foreground: draft.addedTextColor
            )
        }
        .clipShape(.rect(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.separator)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diff color preview")
    }

    private func previewLine(
        prefix: String, text: String, background: NSColor, foreground: NSColor
    ) -> some View {
        HStack(spacing: 10) {
            Text(prefix)
            Text(text)
            Spacer()
        }
        .font(.custom(draft.font.fontName, size: draft.fontSize))
        .foregroundStyle(Color(nsColor: foreground))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: background))
    }
}

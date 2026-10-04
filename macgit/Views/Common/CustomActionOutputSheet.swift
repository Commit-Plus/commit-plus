// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct CustomActionOutputSheet: View {
    let result: CustomActionExecutionResult
    let onRunAgain: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.action.name).font(.headline)
                    Text(statusSummary).foregroundStyle(.secondary)
                }
                Spacer()
            }

            outputSection("Standard Output", text: result.standardOutput, truncated: result.isStandardOutputTruncated)
            outputSection("Standard Error", text: result.standardError, truncated: result.isStandardErrorTruncated)

            HStack {
                Button("Copy Output") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.copiedOutput, forType: .string)
                }
                .disabled(result.copiedOutput.isEmpty)
                Spacer()
                Button("Run Again", action: onRunAgain)
                Button("Close", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 480)
    }

    private func outputSection(_ title: String, text: String, truncated: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                if truncated { Text("Truncated at 1 MB").font(.caption).foregroundStyle(.secondary) }
            }
            TextEditor(text: .constant(text.isEmpty ? "No output" : text))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(.separator) }
                .frame(minHeight: 130)
        }
    }

    private var statusSummary: String {
        var value = result.status.title
        if let exitCode = result.exitCode { value += " · Exit code \(exitCode)" }
        value += String(format: " · %.2fs", result.duration)
        return value
    }

    private var statusIcon: String {
        switch result.status {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle.fill"
        }
    }

    private var statusColor: Color {
        switch result.status {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .orange
        }
    }
}

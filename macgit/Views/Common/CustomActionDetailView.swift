// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// Selected custom action in Settings: summary, actions, and a read-only preview of its script.
struct CustomActionDetailView: View {
    let action: CustomActionDefinition
    let effectiveAction: CustomActionDefinition
    let isTrusted: Bool
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onLocate: () -> Void
    @State private var preview: CustomActionScriptPreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(action.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(sourceDescription)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(sourceDescription)

                HStack(spacing: 8) {
                    Button(isTrusted ? "Edit…" : "Review…", action: onEdit)
                    Button("Duplicate", action: onDuplicate)
                    if effectiveAction.isExecutableMissing {
                        Button("Locate…", action: onLocate)
                    } else if action.sourceKind != .syncedScript {
                        Button("Show in Finder", action: showInFinder)
                    }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            content
        }
        .task(id: previewKey) {
            preview = nil
            preview = await CustomActionScriptPreview.load(for: effectiveAction)
        }
    }

    private var content: some View {
        Group {
            previewContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch preview {
        case nil:
            ProgressView()
                .controlSize(.small)
        case .text(let text):
            ScrollView([.vertical, .horizontal]) {
                Text(text.isEmpty ? " " : text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        case .unavailable(let message):
            ContentUnavailableView(
                "No Preview",
                systemImage: "doc.text.magnifyingglass",
                description: Text(message)
            )
        }
    }

    private var sourceDescription: String {
        switch action.sourceKind {
        case .executable, .localScript: effectiveAction.executablePath
        case .syncedScript: "Synced \(action.scriptLanguage?.displayName ?? "script")"
        }
    }

    private var previewKey: String {
        [effectiveAction.sourceKind.rawValue, effectiveAction.executablePath, effectiveAction.scriptSource ?? ""]
            .joined(separator: "\u{0}")
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: effectiveAction.executablePath)])
    }
}

enum CustomActionScriptPreview: Equatable, Sendable {
    case text(String)
    case unavailable(String)

    private static let maximumPreviewBytes = 512 * 1024

    static func load(for action: CustomActionDefinition) async -> Self {
        if action.sourceKind == .syncedScript {
            return .text(action.scriptSource ?? "")
        }
        let path = action.executablePath
        return await Task.detached(priority: .userInitiated) {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                return .unavailable("The file can’t be found at this path.")
            }
            if let size = attributes[.size] as? Int, size > maximumPreviewBytes {
                return .unavailable("This file is too large to preview.")
            }
            guard let data = FileManager.default.contents(atPath: path) else {
                return .unavailable("The file can’t be read.")
            }
            guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                return .unavailable("This executable is a binary file and can’t be previewed.")
            }
            return .text(text)
        }.value
    }
}

enum CustomActionStatus {
    case disabled
    case fileNotFound
    case needsReview
    case ready

    init(action: CustomActionDefinition, effectiveAction: CustomActionDefinition, isTrusted: Bool) {
        if !action.isEnabled {
            self = .disabled
        } else if effectiveAction.isExecutableMissing {
            self = .fileNotFound
        } else if !isTrusted {
            self = .needsReview
        } else {
            self = .ready
        }
    }

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .fileNotFound: "File Not Found"
        case .needsReview: "Needs Review"
        case .ready: "Ready"
        }
    }

    var systemImage: String {
        switch self {
        case .disabled: "slash.circle"
        case .fileNotFound: "questionmark.circle.fill"
        case .needsReview: "exclamationmark.triangle.fill"
        case .ready: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .disabled: .secondary
        case .fileNotFound, .needsReview: .orange
        case .ready: .green
        }
    }
}

extension CustomActionDefinition {
    /// Whether a file-backed action points at an executable that no longer exists on this Mac.
    var isExecutableMissing: Bool {
        guard sourceKind != .syncedScript else { return false }
        return !FileManager.default.fileExists(atPath: executablePath)
    }
}

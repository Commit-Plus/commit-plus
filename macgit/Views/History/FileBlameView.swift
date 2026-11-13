// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Window content showing who last changed each line of a file at a revision.
struct FileBlameView: View {
    let controller: FileBlameController
    @Environment(\.appTextScale) private var textScale
    @State private var scrollOffset: CGFloat = 0

    private static let gutterWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Blame").font(.headline.scaled(by: textScale))
                FilePathLabel(path: controller.path)
                Spacer(minLength: 8)
                if controller.isLoading { ProgressView().controlSize(.small) }
                revisionControls
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if let error = controller.error {
                VStack {
                    EmptyStateView(icon: "exclamationmark.triangle", message: "Unable to blame file", detail: error)
                    Button("Retry") { controller.load() }.pointingHandCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.lines.isEmpty {
                if controller.isLoading {
                    ProgressView("Loading blame…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(icon: "doc.text", message: "Empty file")
                }
            } else {
                HStack(spacing: 0) {
                    FileBlameGutter(controller: controller, scrollOffset: scrollOffset)
                        .frame(width: Self.gutterWidth * textScale)
                    Divider()
                    CommitFilePreviewContent(lines: controller.lines,
                        fileExtension: SyntaxHighlighter.syntaxIdentifier(forFilePath: controller.path),
                        embedded: true, onVerticalOffsetChange: { scrollOffset = $0 })
                        .id(controller.revision + ":" + controller.path)
                        .overlay {
                            FileBlameBands(controller: controller, scrollOffset: scrollOffset, showsEdgeBar: false)
                                .allowsHitTesting(false)
                        }
                }
            }
        }
        .task { controller.load() }
    }

    private var revisionControls: some View {
        HStack(spacing: 6) {
            ControlGroup {
                Button("Older Revision", systemImage: "chevron.left") {
                    if let entry = controller.olderEntry { controller.show(entry) }
                }
                .disabled(controller.olderEntry == nil)
                .help("Blame the previous revision of this file")
                Button("Newer Revision", systemImage: "chevron.right") {
                    if let entry = controller.newerEntry { controller.show(entry) }
                }
                .disabled(controller.newerEntry == nil)
                .help("Blame the next revision of this file")
            }
            .controlGroupStyle(.navigation)
            .fixedSize()
            Menu {
                if controller.historyIndex == nil || controller.history.isEmpty {
                    Toggle(String(controller.initialRevision.prefix(7)) + "  Selected revision", isOn: Binding(
                        get: { controller.revision == controller.initialRevision },
                        set: { _ in controller.showInitialRevision() }))
                }
                ForEach(controller.history) { entry in
                    Toggle(isOn: Binding(get: { controller.revision == entry.commit.hash },
                                         set: { _ in controller.show(entry) })) {
                        Text("\(entry.commit.shortHash)  \(entry.commit.displaySubject) (\(entry.commit.date.formatted(date: .abbreviated, time: .omitted)))")
                    }
                }
            } label: {
                Text(String(controller.revision.prefix(7)))
                    .font(.system(size: 12, design: .monospaced).scaled(by: textScale))
            }
            .fixedSize()
            .help("Choose the revision to blame")
            .accessibilityLabel("Blame revision")
        }
    }
}

/// Blame annotations aligned with the code rows. Only groups in view are laid out,
/// and a group's label stays pinned while any of its lines are visible.
private struct FileBlameGutter: View {
    let controller: FileBlameController
    let scrollOffset: CGFloat
    @Environment(\.appTextScale) private var textScale

    private let rowHeight = CommitFilePreviewViewport.rowHeight

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                FileBlameBands(controller: controller, scrollOffset: scrollOffset, showsEdgeBar: true)
                ForEach(controller.visibleGroups(offset: scrollOffset, height: geometry.size.height,
                                                 rowHeight: rowHeight)) { group in
                    let top = CGFloat(group.lines.lowerBound) * rowHeight - scrollOffset
                    let lastRowTop = CGFloat(group.lines.upperBound - 1) * rowHeight - scrollOffset
                    // Stick to the top edge while the group is partly scrolled out, never past its last line.
                    label(for: group)
                        .padding(.trailing, FileBlameBands.edgeBarWidth)
                        .frame(width: geometry.size.width, height: rowHeight, alignment: .leading)
                        .offset(y: min(max(top, 0), lastRowTop))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
    }

    @ViewBuilder private func label(for group: FileBlameController.Group) -> some View {
        if let commit = controller.commits[group.hash] {
            let uncommitted = group.hash.allSatisfy { $0 == "0" }
            HStack(spacing: 6) {
                ReflogActorAvatar(name: commit.author, email: commit.email, size: 14)
                Text(uncommitted ? "Not committed yet" : commit.summary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if !uncommitted {
                    Text(commit.date, format: .dateTime.day().month().year())
                        .foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Text(commit.shortHash)
                        .font(.system(size: 11, design: .monospaced).scaled(by: textScale))
                        .foregroundStyle(.secondary).fixedSize()
                }
            }
            .font(.system(size: 11).scaled(by: textScale))
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .help("\(commit.summary)\n\(commit.author) <\(commit.email)>\n\(commit.hash)")
            .contextMenu {
                Button("Copy Commit SHA") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.hash, forType: .string)
                }
            }
        }
    }
}

/// Per-commit tint, divider and optional edge bar for each visible blame group,
/// drawn behind the gutter labels and over the code so both sides share the same bands.
private struct FileBlameBands: View {
    static let edgeBarWidth: CGFloat = 3
    private static let colors: [Color] = [Color(nsColor: .systemBlue), Color(nsColor: .systemOrange), Color(nsColor: .systemGreen)]

    let controller: FileBlameController
    let scrollOffset: CGFloat
    let showsEdgeBar: Bool

    private let rowHeight = CommitFilePreviewViewport.rowHeight

    var body: some View {
        Canvas { context, size in
            let groups = controller.visibleGroups(offset: scrollOffset, height: size.height, rowHeight: rowHeight)
            for index in groups.indices {
                let group = groups[index]
                // Cycling by position guarantees neighbouring groups never share a color.
                let color = Self.colors[index % Self.colors.count]
                // Clamp to the viewport so very long groups do not create huge fills.
                let top = max(-1, CGFloat(group.lines.lowerBound) * rowHeight - scrollOffset)
                let bottom = min(size.height + 1, CGFloat(group.lines.upperBound) * rowHeight - scrollOffset)
                guard bottom > top else { continue }
                context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)),
                             with: .color(color.opacity(showsEdgeBar ? 0.10 : 0.05)))
                if showsEdgeBar {
                    context.fill(Path(CGRect(x: size.width - Self.edgeBarWidth, y: top,
                                             width: Self.edgeBarWidth, height: bottom - top)),
                                 with: .color(color))
                }
                if group.lines.lowerBound > 0, top >= 0 {
                    context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: 1)),
                                 with: .color(color.opacity(0.45)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

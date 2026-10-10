// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreText

/// Shared by the visible hunk canvases. Regex scanning and long-line shaping
/// never run in draw(_:) or in a scroll notification.
@MainActor
final class DiffNativeTextStore {
    nonisolated enum Prepared: Sendable {
        case tokens([(NSRange, SyntaxTokenizer.TokenType)])
        case longLine(DiffLongLineLayout)
    }

    private struct DrawKey: Hashable {
        let lineID: UUID
        let chunk: Int?
        let highlighted: Bool
    }

    private var prepared = DiffGenerationalCache<UUID, Prepared>(capacity: 2_048)
    private var longPrepared = DiffGenerationalCache<UUID, DiffLongLineLayout>(capacity: 8)
    private var drawn = DiffGenerationalCache<DrawKey, CTLine>(capacity: 2_048)
    private var pending: [UUID: DiffLine] = [:]
    private var inFlight: Set<UUID> = []
    private var task: Task<Void, Never>?
    private(set) var generation = 0
    private(set) var fontSize: CGFloat = 12
    private var fileExtension = ""
    private var syntaxHighlighting = false
    var onReady: ((Set<UUID>) -> Void)?

    func reset(fontSize: CGFloat, fileExtension: String, syntaxHighlighting: Bool) {
        cancel()
        generation += 1
        self.fontSize = fontSize
        self.fileExtension = fileExtension
        self.syntaxHighlighting = syntaxHighlighting
        prepared.removeAll()
        longPrepared.removeAll()
        drawn.removeAll()
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending.removeAll()
        inFlight.removeAll()
    }

    func request(_ line: DiffLine) {
        guard syntaxHighlighting || DiffLongLineLayout.isLong(line.text),
            prepared.value(for: line.id) == nil, longPrepared.value(for: line.id) == nil,
            !inFlight.contains(line.id), pending.count < 512
        else { return }
        pending[line.id] = line
        startBatchIfNeeded()
    }

    private func startBatchIfNeeded() {
        guard task == nil, !pending.isEmpty else { return }
        // Short lines are ready first, even when a generated line is also visible.
        let batch = Array(
            pending.values.sorted {
                $0.text.utf8.count < $1.text.utf8.count
            }.prefix(32))
        for line in batch { pending.removeValue(forKey: line.id) }
        inFlight = Set(batch.map(\.id))
        let generation = generation
        let fontSize = fontSize
        let fontName = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular).fontName
        let fileExtension = fileExtension
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                let tokenizer = SyntaxTokenizer(fileExtension: fileExtension)
                var result: [(UUID, Prepared)] = []
                for line in batch {
                    guard !Task.isCancelled else { break }
                    if DiffLongLineLayout.isLong(line.text) {
                        if let layout = DiffLongLineLayout.prepare(
                            text: line.text, fontName: fontName, fontSize: fontSize
                        ) {
                            result.append((line.id, .longLine(layout)))
                        }
                    } else {
                        result.append((line.id, .tokens(tokenizer.tokenRanges(in: line.text))))
                    }
                }
                return result
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            for (id, value) in result {
                if case .longLine(let layout) = value {
                    self.longPrepared.insert(layout, for: id)
                } else {
                    self.prepared.insert(value, for: id)
                }
            }
            self.inFlight.removeAll()
            self.task = nil
            self.onReady?(Set(result.map(\.0)))
            self.startBatchIfNeeded()
        }
    }

    func longLayout(for line: DiffLine) -> DiffLongLineLayout? {
        if let layout = longPrepared.value(for: line.id) { return layout }
        request(line)
        return nil
    }

    func textLine(for line: DiffLine, chunk: Int? = nil, text: String? = nil) -> CTLine {
        let tokens: [(NSRange, SyntaxTokenizer.TokenType)]?
        if chunk == nil, syntaxHighlighting, case .tokens(let value) = prepared.value(for: line.id)
        {
            tokens = value
        } else {
            tokens = nil
        }
        let key = DrawKey(lineID: line.id, chunk: chunk, highlighted: tokens != nil)
        if let cached = drawn.value(for: key) { return cached }
        let string = text ?? line.text
        let value = NSMutableAttributedString(
            string: string,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: line.type == .header
                    ? NSColor.secondaryLabelColor
                    : line.type == .conflictMarker ? NSColor.systemPurple : NSColor.textColor,
            ])
        if chunk == nil, syntaxHighlighting, line.type != .header, line.type != .conflictMarker,
            let tokens
        {
            for (range, type) in tokens {
                if NSMaxRange(range) <= value.length,
                    let color = SyntaxHighlighter.tokenColor(for: type)
                {
                    value.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }
        let result = CTLineCreateWithAttributedString(value)
        drawn.insert(result, for: key)
        #if DEBUG
            DiffRenderStats.lineBuilds += 1
        #endif
        return result
    }
}

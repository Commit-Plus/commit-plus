//
//  CodeEditorView.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let fileExtension: String
    let fontSize: CGFloat

    init(text: Binding<String>, fileExtension: String, fontSize: CGFloat = 12) {
        self._text = text
        self.fileExtension = fileExtension
        self.fontSize = fontSize
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.autoresizingMask = [.width, .height]
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 8
        textView.delegate = context.coordinator
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.allowsUndo = true

        scrollView.documentView = textView

        // Set initial text and highlighting
        textView.string = text
        context.coordinator.attach(to: textView)
        context.coordinator.scheduleHighlighting()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let configurationChanged = context.coordinator.parent.fileExtension != fileExtension
            || context.coordinator.parent.fontSize != fontSize
        context.coordinator.parent = self
        if configurationChanged {
            textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        let currentText = textView.string
        if currentText != text {
            textView.string = text
            context.coordinator.scheduleHighlighting()
        } else if configurationChanged {
            context.coordinator.scheduleHighlighting()
        }
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        private weak var textView: NSTextView?
        private var observer: NSObjectProtocol?
        private var highlightTask: Task<Void, Never>?
        private var applying = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func attach(to view: NSTextView) {
            textView = view
            guard let clip = view.enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                self?.scheduleHighlighting()
            }
        }

        func detach() {
            highlightTask?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
        }

        func scheduleHighlighting() {
            highlightTask?.cancel()
            highlightTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                self?.highlightVisibleText()
            }
        }

        private func highlightVisibleText() {
            guard !applying, let textView, let storage = textView.textStorage,
                  let manager = textView.layoutManager, let container = textView.textContainer else { return }
            let glyphs = manager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let source = storage.string as NSString
            guard characters.location < source.length else { return }
            let visible = source.lineRange(for: characters)
            let highlighter = SyntaxHighlighter(fileExtension: parent.fileExtension)
            applying = true
            let undo = textView.undoManager
            let restoreUndo = undo?.isUndoRegistrationEnabled == true
            if restoreUndo { undo?.disableUndoRegistration() }
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: visible)
            var cursor = visible.location
            while cursor < NSMaxRange(visible) {
                let range = source.lineRange(for: NSRange(location: cursor, length: 0))
                guard range.length > 0 else { break }
                if range.length <= CodeRenderWindow.maximumHighlightedLineLength {
                    let highlighted = highlighter.nsAttributedString(for: source.substring(with: range), fontSize: parent.fontSize)
                    highlighted.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: highlighted.length)) { color, local, _ in
                        guard let color else { return }
                        storage.addAttribute(.foregroundColor, value: color,
                                             range: NSRange(location: range.location + local.location, length: local.length))
                    }
                }
                cursor = NSMaxRange(range)
            }
            storage.endEditing()
            if restoreUndo { undo?.enableUndoRegistration() }
            applying = false
        }

        func textDidChange(_ notification: Notification) {
            guard !applying, let textView else { return }
            parent.text = textView.string
            scheduleHighlighting()
        }
    }
}

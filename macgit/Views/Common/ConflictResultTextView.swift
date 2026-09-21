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
import AppKit
import SwiftUI

struct ConflictResultTextView: NSViewRepresentable {
    let text: String
    let onTextChange: (String) -> Void
    let fileExtension: String
    let baselineText: String
    let colorScheme: ColorScheme
    let isEditable: Bool
    let undoResetGeneration: Int
    let scrollID: String
    let scrollController: SyncedScrollController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = ConflictResultBackgroundLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = ConflictResultNSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(
            width: 8,
            height: ConflictCodeView.verticalPadding
        )
        textView.minSize = NSSize.zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [NSView.AutoresizingMask.height]

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        context.coordinator.textView = textView
        context.coordinator.layoutManager = layoutManager
        context.coordinator.register(
            scrollView: scrollView,
            controller: scrollController,
            id: scrollID
        )
        context.coordinator.apply(parent: self)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.register(
            scrollView: scrollView,
            controller: scrollController,
            id: scrollID
        )
        context.coordinator.apply(parent: self)
        context.coordinator.updateDocumentFrame(viewportSize: scrollView.contentSize)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelPendingPresentationRefresh()
        coordinator.unregister(scrollView: scrollView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: ConflictResultTextView
        weak var textView: NSTextView?
        weak var layoutManager: ConflictResultBackgroundLayoutManager?
        private var isApplyingPresentation = false
        private var hasAppliedPresentation = false
        private var lastHighlightedFileExtension: String?
        private var lastHighlightedColorScheme: ColorScheme?
        private var lastHighlightedBaselineText: String?
        private var lastUndoResetGeneration: Int?
        private var pendingPresentationRefresh: DispatchWorkItem?
        private weak var registeredScrollController: SyncedScrollController?
        private var registeredScrollID: String?
        private var viewportObserver: NSObjectProtocol?
        private var highlightsTask: Task<Void, Never>?
        private var presentationGeneration = 0
        private var lineStarts = [0]
        private var longestLineLength = 0
        private var highlightedRows: Range<Int>?
        private var usesWindowedHighlighting: Bool { lineStarts.count > 2_000 }

        init(parent: ConflictResultTextView) {
            self.parent = parent
        }

        func register(
            scrollView: NSScrollView,
            controller: SyncedScrollController,
            id: String
        ) {
            if registeredScrollController !== controller || registeredScrollID != id {
                unregister(scrollView: scrollView)
            }

            controller.register(scrollView, id: id)
            if viewportObserver == nil {
                viewportObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: scrollView.contentView,
                    queue: .main
                ) { [weak self] _ in
                    self?.highlightVisibleText()
                }
            }
            registeredScrollController = controller
            registeredScrollID = id
        }

        func unregister(scrollView: NSScrollView) {
            if let viewportObserver {
                NotificationCenter.default.removeObserver(viewportObserver)
                self.viewportObserver = nil
            }
            highlightsTask?.cancel()
            guard let registeredScrollController, let registeredScrollID else { return }
            registeredScrollController.unregister(id: registeredScrollID, scrollView: scrollView)
            self.registeredScrollController = nil
            self.registeredScrollID = nil
        }

        func apply(parent: ConflictResultTextView) {
            self.parent = parent
            guard let textView, let layoutManager else { return }

            textView.isEditable = parent.isEditable
            textView.isSelectable = true
            if lastUndoResetGeneration != parent.undoResetGeneration {
                textView.undoManager?.removeAllActions()
                lastUndoResetGeneration = parent.undoResetGeneration
            }

            let hasExternalTextChange = textView.string != parent.text
            let hasPresentationConfigurationChange =
                lastHighlightedFileExtension != parent.fileExtension
                || lastHighlightedColorScheme != parent.colorScheme
                || lastHighlightedBaselineText != parent.baselineText

            guard !hasAppliedPresentation
                    || hasExternalTextChange
                    || hasPresentationConfigurationChange else {
                return
            }

            cancelPendingPresentationRefresh()
            refreshPresentation(
                in: textView,
                layoutManager: layoutManager,
                text: parent.text,
                fileExtension: parent.fileExtension,
                baselineText: parent.baselineText
            )
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingPresentation, let textView else { return }
            highlightsTask?.cancel()
            presentationGeneration += 1
            parent.onTextChange(textView.string)
            schedulePresentationRefresh(for: textView.string)
        }

        func cancelPendingPresentationRefresh() {
            pendingPresentationRefresh?.cancel()
            pendingPresentationRefresh = nil
        }

        private func schedulePresentationRefresh(for expectedText: String) {
            cancelPendingPresentationRefresh()
            guard let textView, let layoutManager else { return }

            let workItem = DispatchWorkItem { [weak self, weak textView, weak layoutManager] in
                guard let self,
                      let textView,
                      let layoutManager,
                      textView.string == expectedText else {
                    return
                }

                self.pendingPresentationRefresh = nil
                self.refreshPresentation(
                    in: textView,
                    layoutManager: layoutManager,
                    text: expectedText,
                    fileExtension: self.parent.fileExtension,
                    baselineText: self.parent.baselineText
                )
            }
            pendingPresentationRefresh = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }

        private func refreshPresentation(
            in textView: NSTextView,
            layoutManager: ConflictResultBackgroundLayoutManager,
            text: String,
            fileExtension: String,
            baselineText: String
        ) {
            lineStarts = [0]
            longestLineLength = 0
            var columns = 0
            for (index, unit) in text.utf16.enumerated() {
                if unit == 10 {
                    lineStarts.append(index + 1)
                    longestLineLength = max(longestLineLength, columns)
                    columns = 0
                } else {
                    columns += unit == 9 ? 8 : 1
                }
            }
            longestLineLength = max(longestLineLength, columns)
            layoutManager.lineStartOffsets = lineStarts
            highlightedRows = nil
            applySyntaxHighlighting(to: textView, text: text, fileExtension: fileExtension)
            highlightsTask?.cancel()
            presentationGeneration += 1
            let generation = presentationGeneration
            layoutManager.changedLineIndices = []
            layoutManager.blankLineIndices = []
            highlightsTask = Task { [weak self, weak layoutManager] in
                let worker = Task.detached(priority: .utility) {
                    let changed = ConflictResultLineHighlights.changedLineIndices(result: text, baseline: baselineText)
                    let blank = ConflictResultLineHighlights.blankLineIndices(in: text)
                    return (changed, blank)
                }
                let (changed, blank) = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self, self.presentationGeneration == generation,
                      let layoutManager else { return }
                layoutManager.changedLineIndices = changed
                layoutManager.blankLineIndices = blank
                layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: text.utf16.count))
            }
            layoutManager.invalidateDisplay(
                forCharacterRange: NSRange(location: 0, length: text.utf16.count)
            )
            if let scrollView = textView.enclosingScrollView {
                updateDocumentFrame(viewportSize: scrollView.contentSize)
            }

            hasAppliedPresentation = true
            lastHighlightedFileExtension = fileExtension
            lastHighlightedColorScheme = parent.colorScheme
            lastHighlightedBaselineText = baselineText
            highlightVisibleText()
        }

        func updateDocumentFrame(viewportSize: NSSize) {
            guard let textView,
                  let layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            let usedSize: NSSize
            if usesWindowedHighlighting {
                usedSize = NSSize(
                    width: CGFloat(longestLineLength) * NSFont.monospacedSystemFont(ofSize: 12, weight: .regular).maximumAdvancement.width,
                    height: CGFloat(lineStarts.count) * ConflictCodeView.rowHeight()
                )
            } else {
                layoutManager.ensureLayout(for: textContainer)
                usedSize = layoutManager.usedRect(for: textContainer).size
            }
            let horizontalInset = textView.textContainerInset.width * 2
            let verticalInset = textView.textContainerInset.height * 2
            textView.frame.size = NSSize(
                width: max(viewportSize.width, usedSize.width + horizontalInset),
                height: max(viewportSize.height, usedSize.height + verticalInset)
            )
            layoutManager.viewportWidth = viewportSize.width
        }

        private func applySyntaxHighlighting(
            to textView: NSTextView,
            text: String,
            fileExtension: String
        ) {
            // Native typing already has the paragraph/font attributes. Replacing
            // the entire storage here would invalidate layout after every pause.
            if usesWindowedHighlighting, hasAppliedPresentation, textView.string == text {
                return
            }
            let selectedRange = textView.selectedRange()
            let highlighted: NSMutableAttributedString
            if usesWindowedHighlighting {
                highlighted = NSMutableAttributedString(string: text, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: ConflictCodeView.defaultFontSize, weight: .regular),
                    .foregroundColor: NSColor.textColor,
                ])
            } else {
                highlighted = NSMutableAttributedString(
                    attributedString: SyntaxHighlighter(fileExtension: fileExtension)
                        .nsAttributedString(for: text, fontSize: ConflictCodeView.defaultFontSize)
                )
            }
            let paragraphStyle = NSMutableParagraphStyle()
            let rowHeight = ConflictCodeView.rowHeight()
            paragraphStyle.minimumLineHeight = rowHeight
            paragraphStyle.maximumLineHeight = rowHeight
            if highlighted.length > 0 {
                highlighted.addAttribute(
                    .paragraphStyle,
                    value: paragraphStyle,
                    range: NSRange(location: 0, length: highlighted.length)
                )
            }

            isApplyingPresentation = true
            let undoManager = textView.undoManager
            let shouldRestoreUndoRegistration = undoManager?.isUndoRegistrationEnabled == true
            if shouldRestoreUndoRegistration {
                undoManager?.disableUndoRegistration()
            }
            textView.textStorage?.setAttributedString(highlighted)
            let textLength = text.utf16.count
            let clampedLocation = min(selectedRange.location, textLength)
            let clampedLength = min(selectedRange.length, textLength - clampedLocation)
            textView.setSelectedRange(
                NSRange(location: clampedLocation, length: clampedLength)
            )
            textView.typingAttributes = [
                .font: NSFont.monospacedSystemFont(
                    ofSize: ConflictCodeView.defaultFontSize,
                    weight: .regular
                ),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle,
            ]
            if shouldRestoreUndoRegistration {
                undoManager?.enableUndoRegistration()
            }
            isApplyingPresentation = false
        }

        private func highlightVisibleText() {
            guard usesWindowedHighlighting, !isApplyingPresentation, pendingPresentationRefresh == nil,
                  let textView, let storage = textView.textStorage,
                  let scrollView = textView.enclosingScrollView else { return }
            let bounds = scrollView.contentView.bounds
            let rows = ConflictRenderWindow.rows(count: lineStarts.count, minY: bounds.minY, height: bounds.height)
            guard rows != highlightedRows, !rows.isEmpty else { return }
            highlightedRows = rows
            let start = lineStarts[rows.lowerBound]
            let end = rows.upperBound < lineStarts.count ? lineStarts[rows.upperBound] : storage.length
            guard start <= end, end <= storage.length else { return }
            let range = NSRange(location: start, length: end - start)
            let source = (storage.string as NSString).substring(with: range)
            let highlighted = SyntaxHighlighter(fileExtension: parent.fileExtension)
                .nsAttributedString(for: source, fontSize: ConflictCodeView.defaultFontSize)
            isApplyingPresentation = true
            let undo = textView.undoManager
            let restoreUndo = undo?.isUndoRegistrationEnabled == true
            if restoreUndo { undo?.disableUndoRegistration() }
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attributes, localRange, _ in
                storage.addAttributes(attributes, range: NSRange(location: start + localRange.location, length: localRange.length))
            }
            storage.endEditing()
            if restoreUndo { undo?.enableUndoRegistration() }
            isApplyingPresentation = false
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// Uses the native preferences toolbar sizing and selection appearance.
struct RepositorySettingsToolbar: NSViewRepresentable {
    @Binding var selection: RepositorySettingsTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> ToolbarAttachmentView {
        let view = ToolbarAttachmentView()
        view.attach = { [weak coordinator = context.coordinator] window in
            coordinator?.install(on: window)
        }
        return view
    }

    func updateNSView(_ view: ToolbarAttachmentView, context: Context) {
        context.coordinator.selection = $selection
        if let window = view.window {
            context.coordinator.install(on: window)
        }
    }

    final class ToolbarAttachmentView: NSView {
        var attach: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { attach?(window) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSToolbarDelegate {
        var selection: Binding<RepositorySettingsTab>
        private let toolbar = NSToolbar(identifier: "RepositorySettings")

        init(selection: Binding<RepositorySettingsTab>) {
            self.selection = selection
            super.init()
            toolbar.delegate = self
            toolbar.displayMode = .iconAndLabel
            toolbar.sizeMode = .small
            toolbar.allowsUserCustomization = false
        }

        func install(on window: NSWindow) {
            if window.toolbar !== toolbar {
                window.toolbar = toolbar
                window.toolbarStyle = .preference
            }
            toolbar.selectedItemIdentifier = identifier(for: selection.wrappedValue)
            window.title = selection.wrappedValue.rawValue
        }

        private func identifier(for tab: RepositorySettingsTab) -> NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(tab.rawValue)
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            RepositorySettingsTab.allCases.map(identifier)
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbar(
            _ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard let tab = RepositorySettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = tab.rawValue
            item.paletteLabel = tab.rawValue
            item.image = NSImage(systemSymbolName: tab.systemImage, accessibilityDescription: tab.rawValue)
            item.target = self
            item.action = #selector(selectTab(_:))
            return item
        }

        @objc private func selectTab(_ sender: NSToolbarItem) {
            guard let tab = RepositorySettingsTab(rawValue: sender.itemIdentifier.rawValue) else { return }
            selection.wrappedValue = tab
        }
    }
}

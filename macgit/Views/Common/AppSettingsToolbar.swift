// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

/// Uses the native preferences toolbar sizing and selection appearance.
struct AppSettingsToolbar: NSViewRepresentable {
    @Binding var selection: AppSettingsSection

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
        var selection: Binding<AppSettingsSection>
        private let toolbar = NSToolbar(identifier: "AppSettings")

        init(selection: Binding<AppSettingsSection>) {
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
            window.title = selection.wrappedValue.title
        }

        private func identifier(for section: AppSettingsSection) -> NSToolbarItem.Identifier {
            NSToolbarItem.Identifier(section.rawValue)
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            AppSettingsSection.allCases.map(identifier)
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
            guard let section = AppSettingsSection(rawValue: itemIdentifier.rawValue) else { return nil }
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = section.title
            item.paletteLabel = section.title
            item.toolTip = section.detail
            item.image = NSImage(systemSymbolName: section.systemImage, accessibilityDescription: section.title)
            item.target = self
            item.action = #selector(selectSection(_:))
            return item
        }

        @objc private func selectSection(_ sender: NSToolbarItem) {
            guard let section = AppSettingsSection(rawValue: sender.itemIdentifier.rawValue) else { return }
            selection.wrappedValue = section
        }
    }
}

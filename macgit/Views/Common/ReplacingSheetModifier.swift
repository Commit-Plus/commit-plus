// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension EnvironmentValues {
    @Entry var sheetPresentationCoordinator: SheetPresentationCoordinator? = nil
}

extension View {
    func sheetPresentationScope() -> some View {
        modifier(SheetPresentationScopeModifier())
    }

    func replacingSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(ReplacingBooleanSheetModifier(
            isPresented: isPresented, onDismiss: onDismiss, sheetContent: content
        ))
    }

    func replacingSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(ReplacingItemSheetModifier(
            item: item, onDismiss: onDismiss, sheetContent: content
        ))
    }
}

private struct SheetPresentationScopeModifier: ViewModifier {
    @State private var coordinator = SheetPresentationCoordinator()

    func body(content: Content) -> some View {
        content.environment(\.sheetPresentationCoordinator, coordinator)
    }
}

private struct ReplacingBooleanSheetModifier<SheetContent: View>: ViewModifier {
    @Environment(\.sheetPresentationCoordinator) private var coordinator
    @State private var id = UUID()
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                // A child sheet must not replace the sheet containing its presenter.
                sheetContent().sheetPresentationScope()
            }
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    coordinator?.present(id) { isPresented = false }
                } else {
                    coordinator?.release(id)
                }
            }
            .onDisappear { coordinator?.release(id) }
    }
}

private struct ReplacingItemSheetModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Environment(\.sheetPresentationCoordinator) private var coordinator
    @State private var id = UUID()
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    @ViewBuilder var sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(item: $item, onDismiss: onDismiss) { value in
                sheetContent(value).sheetPresentationScope()
            }
            .onChange(of: item?.id, initial: true) { _, itemID in
                if itemID != nil {
                    coordinator?.present(id) { item = nil }
                } else {
                    coordinator?.release(id)
                }
            }
            .onDisappear { coordinator?.release(id) }
    }
}

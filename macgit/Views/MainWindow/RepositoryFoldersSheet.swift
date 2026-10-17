// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryFoldersSheet: View {
    @ObservedObject var store: YourRepositoriesStore
    @Environment(\.dismiss) private var dismiss
    @State private var folderToRemove: URL?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Manage Folders").font(.title2.weight(.semibold))
                Text("Folders scanned for Git repositories.").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            Divider()
            if store.folders.isEmpty {
                ContentUnavailableView("No Repository Folders", systemImage: "folder", description: Text("Use Add Folder to choose a folder to scan."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.folders, id: \.self) { folder in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(folder.lastPathComponent).fontWeight(.medium)
                            Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }.help(folder.path)
                        Spacer(minLength: 8)
                        Button("Remove \(folder.lastPathComponent)", systemImage: "minus.circle") { folderToRemove = folder }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }.padding(.vertical, 5)
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 560, height: 400)
        .alert("Remove Folder?", isPresented: Binding(get: { folderToRemove != nil }, set: { if !$0 { folderToRemove = nil } }), presenting: folderToRemove) { folder in
            Button("Remove Folder", role: .destructive) {
                store.removeFolder(folder)
                folderToRemove = nil
            }
            Button("Cancel", role: .cancel) { folderToRemove = nil }
        } message: { folder in
            Text("Remove \(folder.path) from the scan list? The folder and its files will remain on your Mac.")
        }
    }
}

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

struct ReflogView: View {
    let repositoryURL: URL
    let isActive: Bool
    let onShowCommit: (String) -> Void
    let onCreateBranch: (ReflogEntry) -> Void
    @State private var model = ReflogViewModel()
    @State private var needsRefresh = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.errorMessage {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Retry") { reload() }
                }.padding()
            }
            if let entry = model.selectedEntry {
                PersistentHSplit(
                    autosaveName: "ReflogMainSplit",
                    left: { eventTable },
                    right: {
                        ReflogDetailPanel(
                            entry: entry,
                            onClose: { model.selection = nil },
                            onShowCommit: { onShowCommit(entry.hash) },
                            onCreateBranch: { onCreateBranch(entry) }
                        )
                        .frame(minWidth: 320, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    }
                )
            } else {
                eventTable
            }
            Divider()
            HStack {
                Text("\(model.filteredEntries.count) shown · \(model.entries.count) loaded").foregroundStyle(.secondary)
                Spacer()
                if model.isLoading && !model.entries.isEmpty { ProgressView().controlSize(.small) }
                if model.hasMore {
                    Button("Load Older Events") { Task { await model.load(in: repositoryURL, more: true) } }
                        .disabled(model.isLoading)
                }
            }.padding(10)
        }
        .task(id: repositoryURL.absoluteString + String(model.allReferences)) {
            guard isActive else {
                needsRefresh = true
                return
            }
            await model.load(in: repositoryURL, reset: true)
            needsRefresh = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryDidChange)) { notification in
            refresh(for: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .repositoryLocalStateDidRefresh)) { notification in
            refresh(for: notification)
        }
        .onChange(of: isActive) { _, active in
            guard active, needsRefresh else { return }
            reload()
        }
    }

    private var eventTable: some View {
        Table(model.filteredEntries, selection: $model.selection) {
            TableColumn("Action") { entry in
                ReflogActionChip(action: entry.action)
                    .onAppear {
                        Task { await model.loadMoreIfNeeded(for: entry, in: repositoryURL) }
                    }
            }.width(min: 100, ideal: 130)
            TableColumn("Event") { entry in Text(entry.message).help(entry.message) }.width(min: 200, ideal: 360)
            TableColumn("Commit") { entry in Text(entry.hash.prefix(10)).monospaced() }.width(95)
            if model.selectedEntry == nil {
                TableColumn("Reference", value: \.reference).width(min: 90, ideal: 140)
                TableColumn("Who", value: \.actor).width(min: 90, ideal: 130)
                TableColumn("When") { entry in
                    if let date = entry.date {
                        Text(date, format: .dateTime.year().month().day().hour().minute().second())
                    } else { Text("Unknown") }
                }.width(min: 150, ideal: 180)
            }
        }
        .contextMenu(forSelectionType: ReflogEntry.ID.self) { ids in
            if let entry = model.entries.first(where: { ids.contains($0.id) }) {
                Button("Show Commit") { onShowCommit(entry.hash) }
                Button("Create Branch from Commit…") { onCreateBranch(entry) }
                Button("Copy Commit Hash") { copy(entry.hash) }
                Button("Copy Event") { copy(entry.message) }
            }
        } primaryAction: { ids in
            if let entry = model.entries.first(where: { ids.contains($0.id) }) { onShowCommit(entry.hash) }
        }
        .overlay {
            if model.entries.isEmpty && model.isLoading {
                ProgressView("Loading reflog…")
            } else if model.filteredEntries.isEmpty && model.errorMessage == nil {
                ContentUnavailableView(
                    model.query.isEmpty ? "No Reflog Entries" : "No Matching Events",
                    systemImage: "list.bullet.rectangle",
                    description: Text(model.query.isEmpty ? "Local reference updates will appear here after Git operations." : "Try another search or load older events.")
                )
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Reflog").font(.title2.bold())
                Picker("Scope", selection: $model.allReferences) {
                    Text("HEAD").tag(false)
                    Text("All References").tag(true)
                }.frame(width: 210)
                Spacer()
                TextField("Search loaded events", text: $model.query).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Button("Refresh", systemImage: "arrow.clockwise") { reload() }.disabled(model.isLoading)
            }
            Text("Local reference history, including checkout, reset and rebase. Entries can expire; create a branch to keep a recovered commit.")
                .font(.callout).foregroundStyle(.secondary)
        }.padding()
    }

    private func refresh(for notification: Notification) {
        guard let url = notification.userInfo?["repositoryURL"] as? URL,
              url.standardizedFileURL == repositoryURL.standardizedFileURL else { return }
        needsRefresh = true
        if isActive { reload() }
    }

    private func reload() {
        Task {
            await model.load(in: repositoryURL)
            guard !Task.isCancelled else { return }
            needsRefresh = false
        }
    }
    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

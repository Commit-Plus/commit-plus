// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct GitProviderRepositoryBrowser: View {
    var resolver: GitProviderCredentialResolver
    var onSelect: (String, String) -> Void
    @State private var selectedAccountID = ""
    @State private var repositories: [GitProviderDiscoveredRepository] = []
    @State private var page = 1
    @State private var hasNextPage = false
    @State private var retryID = 0
    @State private var loading = false
    @State private var errorMessage: String?

    private var accounts: [GitProviderAccount] {
        resolver.accounts.filter { $0.provider != .bitbucket && ($0.transportProtocol == .https || $0.permissions["authentication"] == "personalAccessToken" || !$0.scopes.isEmpty) }
    }

    var body: some View {
        if !accounts.isEmpty {
            DisclosureGroup("Browse connected repositories") {
                Picker("Account", selection: $selectedAccountID) {
                    Text("Choose account").tag("")
                    ForEach(accounts) { account in
                        Text("\(account.username) — \(GitProviderHost.identityKey(account.hostURL))").tag(account.id)
                    }
                }
                .onChange(of: selectedAccountID) { _, _ in repositories = []; page = 1; hasNextPage = false; errorMessage = nil }
                if loading { ProgressView("Loading repositories...").controlSize(.small) }
                if !repositories.isEmpty {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(repositories) { repository in
                                Button(repository.name) { onSelect(repository.cloneURL, selectedAccountID) }
                                    .buttonStyle(.link)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                }
                if hasNextPage && errorMessage == nil { Button("Load more") { page += 1 }.disabled(loading) }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Button("Retry") { retryID += 1 }.disabled(loading)
                } else if !selectedAccountID.isEmpty && !loading && repositories.isEmpty {
                    Text("No repositories available for this account.").foregroundStyle(.secondary)
                }
            }
            .task(id: "\(selectedAccountID):\(page):\(retryID)") {
                await loadRepositories()
            }
        }
    }

    private func loadRepositories() async {
        guard let account = accounts.first(where: { $0.id == selectedAccountID }) else { loading = false; return }
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        do {
            let result = try await GitProviderRepositoryDiscoveryService().repositories(account: account, resolver: resolver, page: page)
            try Task.checkCancellation()
            repositories += result.repositories.filter { new in !repositories.contains(where: { $0.id == new.id }) }
            hasNextPage = result.hasNextPage
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = GitProviderAuthError.connectionMessage(error)
        }
    }
}

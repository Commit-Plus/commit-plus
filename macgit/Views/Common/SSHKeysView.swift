// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Lists the SSH keys in `~/.ssh`, creates new ones, and shows the public key to add to a Git provider.
struct SSHKeysView: View {
    @State private var viewModel = SSHKeysViewModel()
    @State private var isGeneratingKey = false
    @State private var isAddingToKeychain = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("1. Select or generate an SSH key that identifies this Mac.")
                Text("2. Copy the public key to the SSH keys section of your Git provider account.")
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                keyList
                    .frame(width: Self.listWidth)

                detailPanel
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                ControlGroup {
                    Button("Generate Key", systemImage: "plus") { isGeneratingKey = true }
                        .help("Generate a new SSH key")

                    Button("Reload Keys", systemImage: "arrow.clockwise") {
                        Task { await viewModel.reload() }
                    }
                    .help("Reload keys from \(abbreviatedPath(viewModel.sshDirectoryPath))")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                .disabled(viewModel.isWorking)

                if viewModel.isWorking {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                footerStatus

                Button("Done") { dismissWindow() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 460)
        .task { await viewModel.reload() }
        .sheet(isPresented: $isGeneratingKey) {
            SSHKeyGenerateSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isAddingToKeychain) {
            SSHKeyKeychainSheet(viewModel: viewModel)
        }
    }

    private static let listWidth: CGFloat = 240

    private var keyList: some View {
        List(viewModel.keys, selection: $viewModel.selectedKeyID) { key in
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(key.keyType ?? "Unknown type")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(key.id)
        }
        .settingsTableStyle()
        .overlay {
            if viewModel.keys.isEmpty, !viewModel.isLoading {
                ContentUnavailableView(
                    "No SSH Keys",
                    systemImage: "key",
                    description: Text("Generate a key with the + button.")
                )
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var detailPanel: some View {
        Group {
            if let key = viewModel.selectedKey {
                detail(for: key)
            } else {
                ContentUnavailableView(
                    "No Key Selected",
                    systemImage: "key",
                    description: Text("Select a key to see its public key, or generate a new one.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .settingsDetailPanelStyle()
    }

    private func detail(for key: SSHKeyPair) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(key.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(key.privateKeyURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(key.privateKeyURL.path)

                HStack(spacing: 8) {
                    Button("Copy Public Key") { viewModel.copyPublicKey(key) }
                    Button("Show in Finder") { viewModel.revealInFinder(key) }
                    Button("Add to Keychain…") { isAddingToKeychain = true }
                        .help("Load the key into ssh-agent and save its passphrase in the macOS Keychain")
                    Menu("Add to Provider") {
                        ForEach(SSHKeyProviderLink.all) { link in
                            Link(link.title, destination: link.url)
                        }
                    }
                    .fixedSize()
                }
                .controlSize(.small)
                .disabled(viewModel.isWorking)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Type").foregroundStyle(.secondary)
                            Text(key.keyType ?? "Unknown")
                        }
                        GridRow {
                            Text("SHA256").foregroundStyle(.secondary)
                            Text(key.fingerprint.map { String($0.dropFirst("SHA256:".count)) } ?? "Unavailable")
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Public Key").foregroundStyle(.secondary)
                        Text(key.publicKey)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private var footerStatus: some View {
        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(2)
        } else if let statusMessage = viewModel.statusMessage {
            Label(statusMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(2)
        } else {
            Text("Git uses these keys through the system ssh-agent and ~/.ssh/config.")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

struct SSHKeyProviderLink: Identifiable {
    var title: String
    var url: URL

    var id: String { title }

    static let all: [SSHKeyProviderLink] = [
        SSHKeyProviderLink(title: "GitHub", url: URL(string: "https://github.com/settings/ssh/new")!),
        SSHKeyProviderLink(title: "GitLab", url: URL(string: "https://gitlab.com/-/user_settings/ssh_keys")!),
        SSHKeyProviderLink(title: "Bitbucket", url: URL(string: "https://bitbucket.org/account/settings/ssh-keys/")!)
    ]
}

private struct SSHKeyGenerateSheet: View {
    var viewModel: SSHKeysViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: SSHKeyType = .ed25519
    @State private var fileName = ""
    @State private var comment = ""
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var canGenerate: Bool {
        SSHKeyService.isValidFileName(fileName.trimmingCharacters(in: .whitespacesAndNewlines))
            && passphrase == confirmation
            && !viewModel.isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Generate SSH Key").font(.headline)

            Form {
                Picker("Type", selection: $type) {
                    ForEach(SSHKeyType.allCases) { Text($0.title).tag($0) }
                }
                TextField("File Name", text: $fileName, prompt: Text(type.defaultFileName))
                TextField("Comment", text: $comment, prompt: Text("you@example.com"))
                SecureField("Passphrase", text: $passphrase, prompt: Text("Optional"))
                SecureField("Confirm", text: $confirmation)
                if passphrase != confirmation, !confirmation.isEmpty {
                    Text("The passphrases do not match.").foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            Text("The key is saved in \((viewModel.sshDirectoryPath as NSString).abbreviatingWithTildeInPath). A passphrase is stored in the macOS Keychain so Commit+ can use the key without asking.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if viewModel.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Generate") {
                    Task {
                        let request = SSHKeyGenerationRequest(type: type, fileName: fileName, comment: comment, passphrase: passphrase)
                        if await viewModel.generate(request) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canGenerate)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { fileName = viewModel.suggestedFileName(for: type) }
        .onChange(of: type) { oldType, newType in
            if fileName == viewModel.suggestedFileName(for: oldType) || fileName.isEmpty {
                fileName = viewModel.suggestedFileName(for: newType)
            }
        }
    }
}

private struct SSHKeyKeychainSheet: View {
    var viewModel: SSHKeysViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add \(viewModel.selectedKey?.name ?? "Key") to Keychain").font(.headline)
            Text("Loads the key into ssh-agent and saves its passphrase in the macOS Keychain, so Git can use it without a Terminal prompt. Leave the passphrase empty for a key without one.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Passphrase", text: $passphrase)
            HStack {
                if viewModel.isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    Task {
                        if await viewModel.addSelectedKeyToKeychain(passphrase: passphrase) { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isWorking)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

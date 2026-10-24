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
import Foundation
import Observation

@MainActor
@Observable
final class GitSettingsViewModel {
    var settings = GlobalGitSettings.empty
    var selectedRuntimePreference = GitRuntimePreference.automatic
    var credentialHelperMode = GitCredentialHelperMode.commitPlusAccountsOnly
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isDownloadingEmbeddedGit = false
    private(set) var savedSettings = GlobalGitSettings.empty
    private(set) var statusMessage: String?
    private(set) var saveErrorMessage: String?
    private(set) var systemRuntime: GitRuntimeInstallation?
    private(set) var embeddedRuntime: GitRuntimeInstallation?
    private(set) var activeRuntime: GitRuntimeInstallation?
    private(set) var embeddedVersion = ""
    private(set) var embeddedDownloadSize = 0
    private(set) var availableCredentialHelpers: [String] = []
    private(set) var savedCredentialHelperMode = GitCredentialHelperMode.commitPlusAccountsOnly
    var errorMessage: String?
    var showingError = false
    var showingCredentialHelperReplacementConfirmation = false

    /// The text field being edited; its value is not saved until editing ends.
    @ObservationIgnored var editingTextField: WritableKeyPath<GlobalGitSettings, String>?
    @ObservationIgnored private var credentialHelperModeAwaitingConfirmation: GitCredentialHelperMode?
    private static var latestSave: Task<Void, Never>?
    @ObservationIgnored private let service: GitStatusService
    @ObservationIgnored private let runtimeManager: GitRuntimeManager
    @ObservationIgnored private let fileManager: FileManager

    init(
        service: GitStatusService = .shared,
        runtimeManager: GitRuntimeManager = .shared,
        fileManager: FileManager = .default
    ) {
        self.service = service
        self.runtimeManager = runtimeManager
        self.fileManager = fileManager
    }

    var isBusy: Bool {
        isLoading || isSaving || isDownloadingEmbeddedGit
    }

    var embeddedDownloadSizeDescription: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(embeddedDownloadSize),
            countStyle: .file
        )
    }

    var visibleRuntime: GitRuntimeInstallation? {
        switch selectedRuntimePreference {
        case .automatic:
            return activeRuntime
        case .system:
            return systemRuntime
        case .embedded:
            return embeddedRuntime
        }
    }

    var visibleRuntimeTitle: String {
        switch selectedRuntimePreference {
        case .system:
            return "System Git"
        case .embedded:
            return "Embedded Git"
        case .automatic:
            return activeRuntime?.executableURL == embeddedRuntime?.executableURL
                ? "Embedded Git"
                : "System Git"
        }
    }

    var visibleRuntimeSystemImage: String {
        visibleRuntimeTitle == "Embedded Git" ? "shippingbox" : "desktopcomputer"
    }

    var shouldOfferEmbeddedDownload: Bool {
        embeddedRuntime == nil
            && selectedRuntimePreference != .system
            && (selectedRuntimePreference == .embedded || activeRuntime == nil)
    }

    var credentialHelperChoices: [String] {
        var choices = availableCredentialHelpers
        if case .helper(let helper) = credentialHelperMode, !choices.contains(helper) {
            choices.append(helper)
        }
        return choices
    }

    var hasMultipleCredentialHelpers: Bool {
        savedCredentialHelperMode == .preserveExisting
    }

    var selectedCredentialHelperIsInsecure: Bool {
        guard case .helper(let helper) = credentialHelperMode else { return false }
        return isInsecureCredentialStore(helper)
    }

    var configuredCredentialsUseInsecureStore: Bool {
        selectedCredentialHelperIsInsecure
            || GitCredentialHelperMode.effectiveValues(
                configuredValues: settings.credentialHelperValues
            ).contains(where: isInsecureCredentialStore)
    }

    var credentialHelperAvailability: (title: String, systemImage: String, isAvailable: Bool)? {
        guard case .helper(let helper) = credentialHelperMode else { return nil }
        return availability(for: helper)
    }

    func availability(for helper: String) -> (title: String, systemImage: String, isAvailable: Bool) {
        if availableCredentialHelpers.contains(helper) {
            return ("Available to \(visibleRuntimeTitle)", "checkmark.circle.fill", true)
        }
        if helper.hasPrefix("!") || helper.hasPrefix("/") || helper.contains(where: \Character.isWhitespace) {
            return ("Custom helper; availability is not verified", "questionmark.circle", false)
        }
        return ("Not available to \(visibleRuntimeTitle)", "exclamationmark.triangle.fill", false)
    }

    func load() async {
        await Self.latestSave?.value
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        await refreshRuntimeStatus()

        do {
            let loaded = try await service.loadGlobalGitSettings()
            settings = loaded
            savedSettings = loaded
            credentialHelperMode = GitCredentialHelperMode.resolve(
                configuredValues: loaded.credentialHelperValues
            )
            savedCredentialHelperMode = credentialHelperMode
            availableCredentialHelpers = await service.availableCredentialHelpers()
        } catch {
            present(error)
        }
    }

    /// Queues a save after any save already requested, from this or an earlier instance of the pane.
    /// `committing` names a text field whose current value should be saved even while it is being edited.
    func requestSave(
        committing committedField: WritableKeyPath<GlobalGitSettings, String>? = nil,
        allowCredentialHelperReplacement: Bool = false
    ) {
        let previous = Self.latestSave
        // Holds the view model strongly so a save requested as the pane closes still finishes.
        Self.latestSave = Task {
            await previous?.value
            await self.save(
                committing: committedField,
                allowCredentialHelperReplacement: allowCredentialHelperReplacement
            )
        }
    }

    /// Writes committed changes to the global Git config. The text field being edited is left out
    /// until editing ends, a credential helper replacement waits for confirmation without blocking
    /// other fields, and validation failures are shown inline rather than as alerts.
    func save(
        committing committedField: WritableKeyPath<GlobalGitSettings, String>? = nil,
        allowCredentialHelperReplacement: Bool = false
    ) async {
        guard !isLoading, !isSaving else { return }

        var submittedSettings = settings
        if let editingTextField, editingTextField != committedField {
            submittedSettings[keyPath: editingTextField] = savedSettings[keyPath: editingTextField]
        }
        let previousSavedCredentialHelperMode = savedCredentialHelperMode
        var submittedCredentialHelperMode = credentialHelperMode == savedCredentialHelperMode
            ? nil
            : credentialHelperMode
        if let mode = submittedCredentialHelperMode,
           hasMultipleCredentialHelpers,
           mode != .preserveExisting,
           !allowCredentialHelperReplacement {
            submittedCredentialHelperMode = nil
            if credentialHelperModeAwaitingConfirmation != mode {
                credentialHelperModeAwaitingConfirmation = mode
                showingCredentialHelperReplacementConfirmation = true
            }
        }
        guard submittedSettings != savedSettings || submittedCredentialHelperMode != nil else {
            // Nothing committed differs from the config, so an earlier failure no longer applies.
            saveErrorMessage = nil
            return
        }
        isSaving = true
        statusMessage = nil
        defer { isSaving = false }

        var saveError: Error?
        do {
            try await service.updateGlobalGitSettings(
                submittedSettings,
                previous: savedSettings,
                credentialHelperMode: submittedCredentialHelperMode
            )
        } catch {
            saveError = error
        }

        // Reload even after a failure, since fields that passed validation were still written.
        let loaded: GlobalGitSettings
        do {
            loaded = try await service.loadGlobalGitSettings()
        } catch {
            saveErrorMessage = (saveError ?? error).localizedDescription
            return
        }
        savedSettings = loaded
        savedCredentialHelperMode = GitCredentialHelperMode.resolve(
            configuredValues: loaded.credentialHelperValues
        )
        // Keep edits made during the save and values that failed validation, so they can be corrected.
        if saveError == nil {
            settings = mergingLoadedSettings(loaded, submitted: submittedSettings)
        } else {
            settings.credentialHelperValues = loaded.credentialHelperValues
        }
        if credentialHelperMode == (submittedCredentialHelperMode ?? previousSavedCredentialHelperMode) {
            credentialHelperMode = savedCredentialHelperMode
        }
        if submittedCredentialHelperMode != nil {
            credentialHelperModeAwaitingConfirmation = nil
            showingCredentialHelperReplacementConfirmation = false
        }
        availableCredentialHelpers = await service.availableCredentialHelpers()

        if let saveError {
            saveErrorMessage = saveError.localizedDescription
        } else {
            saveErrorMessage = nil
            statusMessage = "Saved to global Git config."
        }
    }

    /// Resetting the mode triggers the view's credential helper autosave, which saves anything else pending.
    func cancelCredentialHelperReplacement() {
        credentialHelperModeAwaitingConfirmation = nil
        showingCredentialHelperReplacementConfirmation = false
        credentialHelperMode = savedCredentialHelperMode
    }

    func selectRuntimePreference(_ preference: GitRuntimePreference) async {
        statusMessage = nil

        if preference == .embedded, embeddedRuntime == nil {
            statusMessage = "Download Embedded Git to use this option."
            return
        }

        do {
            try await runtimeManager.setPreference(preference)
            await refreshRuntimeStatus()
            applyActiveRuntimeToSettings()
            availableCredentialHelpers = await service.availableCredentialHelpers()
            statusMessage = "\(preference.title) is now active."
        } catch {
            await refreshRuntimeStatus()
            present(error)
        }
    }

    func downloadEmbeddedGit() async {
        guard !isDownloadingEmbeddedGit else { return }
        isDownloadingEmbeddedGit = true
        statusMessage = nil
        defer { isDownloadingEmbeddedGit = false }

        do {
            try await runtimeManager.installEmbeddedRuntime()
            try await runtimeManager.setPreference(.embedded)
            await refreshRuntimeStatus()
            applyActiveRuntimeToSettings()
            availableCredentialHelpers = await service.availableCredentialHelpers()
            statusMessage = "Embedded Git \(embeddedVersion) installed and selected."
        } catch {
            await refreshRuntimeStatus()
            present(error)
        }
    }

    func chooseGlobalIgnoreFile() {
        let panel = NSSavePanel()
        panel.title = "Choose Global Git Ignore File"
        panel.prompt = "Choose"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = expandedURL(for: settings.excludesFilePath).lastPathComponent

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.excludesFilePath = abbreviatedPath(for: url)
        statusMessage = nil
    }

    func useDefaultGlobalIgnoreFile() {
        settings.excludesFilePath = "~/.config/git/ignore"
        statusMessage = nil
    }

    func openGlobalIgnoreFile() {
        let trimmedPath = settings.excludesFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            present(GitError.commandFailed("Choose a global ignore file first."))
            return
        }
        openFile(at: expandedURL(for: trimmedPath))
    }

    func openGlobalGitConfig() {
        openFile(at: fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".gitconfig"))
    }

    private func openFile(at url: URL) {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: url.path) {
                guard fileManager.createFile(atPath: url.path, contents: Data()) else {
                    throw GitError.commandFailed("Could not create \(url.path).")
                }
            }
            guard NSWorkspace.shared.open(url) else {
                throw GitError.commandFailed("Could not open \(url.path).")
            }
        } catch {
            present(error)
        }
    }

    private func expandedURL(for path: String) -> URL {
        let expandedPath = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    private func abbreviatedPath(for url: URL) -> String {
        let homePath = fileManager.homeDirectoryForCurrentUser.path
        guard url.path == homePath || url.path.hasPrefix(homePath + "/") else {
            return url.path
        }
        return "~" + url.path.dropFirst(homePath.count)
    }

    private func present(_ error: Error) {
        errorMessage = error.localizedDescription
        showingError = true
    }

    private func isInsecureCredentialStore(_ helper: String) -> Bool {
        helper.split(whereSeparator: \Character.isWhitespace).first == "store"
    }

    /// Takes the loaded value for each field the user has not changed since the save was submitted.
    private func mergingLoadedSettings(
        _ loaded: GlobalGitSettings,
        submitted: GlobalGitSettings
    ) -> GlobalGitSettings {
        var merged = loaded
        let textFields: [WritableKeyPath<GlobalGitSettings, String>] = [
            \.userName, \.userEmail, \.defaultBranchName, \.excludesFilePath
        ]
        for field in textFields where settings[keyPath: field] != submitted[keyPath: field] {
            merged[keyPath: field] = settings[keyPath: field]
        }
        let toggles: [WritableKeyPath<GlobalGitSettings, Bool>] = [\.pruneOnFetch, \.autoSetupRemote]
        for field in toggles where settings[keyPath: field] != submitted[keyPath: field] {
            merged[keyPath: field] = settings[keyPath: field]
        }
        return merged
    }

    private func refreshRuntimeStatus() async {
        let status = await runtimeManager.status()
        selectedRuntimePreference = status.preference
        systemRuntime = status.systemRuntime
        embeddedRuntime = status.embeddedRuntime
        activeRuntime = status.activeRuntime
        embeddedVersion = status.embeddedVersion
        embeddedDownloadSize = status.embeddedDownloadSize
    }

    /// The runtime fields are informational and not written to the Git config, so they never count as unsaved.
    private func applyActiveRuntimeToSettings() {
        settings.executablePath = activeRuntime?.executableURL.path ?? ""
        settings.version = activeRuntime?.version ?? ""
        savedSettings.executablePath = settings.executablePath
        savedSettings.version = settings.version
    }
}

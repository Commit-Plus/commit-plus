// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class RepositoryFileOpenModel {
    var request: SearchFileOpenRequest?
    var error: String?
    private var file: URL?

    func prepare(_ file: URL, appState: AppState) {
        self.file = file
        let applications = SearchFileApplicationResolver.availableApplications()
        if let preferred = appState.preferredSearchFileApplicationBundleIdentifier {
            if let application = applications.first(where: { $0.bundleIdentifier == preferred }) {
                open(file, using: application)
                return
            }
            appState.preferredSearchFileApplicationBundleIdentifier = nil
        }
        guard !applications.isEmpty else {
            error = "No supported application is available to open this file."
            return
        }
        request = SearchFileOpenRequest(relativePath: file.lastPathComponent, applications: applications)
    }

    func choose(_ application: SearchFileApplication, remember: Bool, appState: AppState) {
        guard let file else { return }
        if remember { appState.preferredSearchFileApplicationBundleIdentifier = application.bundleIdentifier }
        request = nil
        open(file, using: application)
    }

    private func open(_ file: URL, using application: SearchFileApplication) {
        Task {
            do {
                try await SearchFileOpener.open(relativePath: file.lastPathComponent, in: file.deletingLastPathComponent(), using: application)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

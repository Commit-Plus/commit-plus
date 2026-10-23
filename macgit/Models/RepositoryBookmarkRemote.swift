// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct RepositoryBookmarkRemote: Identifiable, Equatable {
    let name: String
    let identity: RepositoryBookmarkIdentity

    var id: String { name }

    var webURL: URL {
        let url = identity.canonicalRemoteURL
        return url.path.hasSuffix(".git") ? url.deletingPathExtension() : url
    }

    var issuesURL: URL? {
        switch identity.provider {
        case .github, .bitbucket: webURL.appending(path: "issues")
        case .gitlab: webURL.appending(path: "-/issues")
        // Azure Repos has no per-repository issues page.
        case .azureDevOps, .generic: nil
        }
    }

    var pullRequestsURL: URL? {
        switch identity.provider {
        case .github: webURL.appending(path: "pulls")
        case .gitlab: webURL.appending(path: "-/merge_requests")
        case .bitbucket: webURL.appending(path: "pull-requests")
        case .azureDevOps: webURL.appending(path: "pullrequests")
        case .generic: nil
        }
    }
}

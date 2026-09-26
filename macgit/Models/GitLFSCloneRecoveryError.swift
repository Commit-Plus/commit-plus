// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct GitLFSCloneRecoveryError: LocalizedError {
    let repository: URL
    let reason: String
    var errorDescription: String? {
        "Git clone completed, but Git LFS content is not ready. You can open the repository and finish setup/download in Git LFS.\n\n\(reason)"
    }
}

// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSFileList: Decodable, Sendable {
    let files: [GitLFSFile]?
}

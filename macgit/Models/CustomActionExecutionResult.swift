// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum CustomActionExecutionStatus: Equatable, Sendable {
    case succeeded
    case failed
    case cancelled

    var title: String {
        switch self {
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

struct CustomActionExecutionResult: Equatable, Sendable {
    let action: CustomActionDefinition
    let context: CustomActionInvocationContext
    let status: CustomActionExecutionStatus
    let exitCode: Int32?
    let standardOutput: String
    let standardError: String
    let isStandardOutputTruncated: Bool
    let isStandardErrorTruncated: Bool
    let duration: TimeInterval

    var copiedOutput: String {
        var sections: [String] = []
        if !standardOutput.isEmpty { sections.append("stdout:\n\(standardOutput)") }
        if !standardError.isEmpty { sections.append("stderr:\n\(standardError)") }
        return sections.joined(separator: "\n\n")
    }
}

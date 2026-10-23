// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// An Azure Repos (Azure DevOps Services) repository parsed from any supported remote form:
/// `https://[user@]dev.azure.com/{org}/{project}/_git/{repo}`,
/// `https://{org}.visualstudio.com[/DefaultCollection]/{project}/_git/{repo}`,
/// `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}` and
/// `{org}@vs-ssh.visualstudio.com:v3/{org}/{project}/{repo}`.
struct AzureReposRemote: Equatable {
    static let host = "dev.azure.com"

    /// Organization as written in the remote; compare with `organizationKey`.
    var organization: String
    var project: String
    var repository: String

    var organizationKey: String { organization.lowercased() }

    /// Account host and credential-matching key, with the organization lowercased.
    var organizationURL: URL { Self.organizationURL(organization) }

    var canonicalURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "/\(organization)/\(project)/_git/\(repository)"
        return components.url!
    }

    var pullRequestsURL: URL { canonicalURL.appending(path: "pullrequests") }

    func pullRequestCreateURL(sourceBranch: String) -> URL? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let branch = sourceBranch.addingPercentEncoding(withAllowedCharacters: allowed) ?? sourceBranch
        return URL(string: canonicalURL.absoluteString + "/pullrequestcreate?sourceRef=" + branch)
    }

    static func organizationURL(_ organization: String) -> URL {
        URL(string: "https://\(host)/\(organization.lowercased())")!
    }

    static func parse(_ remoteURLString: String) -> AzureReposRemote? {
        let trimmed = remoteURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        let host: String
        let rawPath: String
        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed),
                  let scheme = components.scheme?.lowercased(),
                  ["https", "http", "ssh"].contains(scheme),
                  let parsedHost = components.host?.lowercased() else { return nil }
            host = parsedHost
            rawPath = components.percentEncodedPath
        } else {
            // scp-like syntax: user@host:path
            guard let at = trimmed.firstIndex(of: "@"),
                  let colon = trimmed[at...].firstIndex(of: ":") else { return nil }
            host = trimmed[trimmed.index(after: at)..<colon].lowercased()
            rawPath = String(trimmed[trimmed.index(after: colon)...])
        }

        var parts: [String] = []
        for part in rawPath.split(separator: "/") {
            guard let decoded = String(part).removingPercentEncoding,
                  !decoded.isEmpty, !decoded.contains("/") else { return nil }
            parts.append(decoded)
        }

        switch host {
        case "ssh.dev.azure.com", "vs-ssh.visualstudio.com":
            guard parts.count == 4, parts[0].lowercased() == "v3" else { return nil }
            return make(organization: parts[1], project: parts[2], repository: parts[3])
        case Self.host:
            guard let organization = parts.first else { return nil }
            return make(organization: organization, gitPath: Array(parts.dropFirst()))
        case let legacyHost where legacyHost.hasSuffix(".visualstudio.com"):
            let organization = String(host.dropLast(".visualstudio.com".count))
            guard !organization.contains(".") else { return nil }
            var gitPath = parts
            if gitPath.first?.lowercased() == "defaultcollection" { gitPath.removeFirst() }
            return make(organization: organization, gitPath: gitPath)
        default:
            return nil
        }
    }

    /// Resolves an organization name, `https://dev.azure.com/{org}[/...]`, or `{org}.visualstudio.com`.
    static func organization(fromInput value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        guard trimmed.contains("://") || trimmed.contains(".") || trimmed.contains("/") else {
            return isValidOrganization(trimmed) ? trimmed : nil
        }
        guard let components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased() else { return nil }
        let organization: String?
        if host == Self.host {
            organization = components.path.split(separator: "/").first.map(String.init)
        } else if host.hasSuffix(".visualstudio.com") {
            organization = String(host.dropLast(".visualstudio.com".count))
        } else {
            organization = nil
        }
        guard let organization, isValidOrganization(organization) else { return nil }
        return organization
    }

    static func isValidOrganization(_ value: String) -> Bool {
        guard (1...50).contains(value.count),
              value.first?.isLetter == true || value.first?.isNumber == true else { return false }
        return value.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
    }

    /// `gitPath` is `{project}/_git/{repo}`, or `_git/{repo}` when the project and repository share a name.
    private static func make(organization: String, gitPath: [String]) -> AzureReposRemote? {
        if gitPath.count == 3, gitPath[1] == "_git" {
            return make(organization: organization, project: gitPath[0], repository: gitPath[2])
        }
        if gitPath.count == 2, gitPath[0] == "_git" {
            return make(organization: organization, project: gitPath[1], repository: gitPath[1])
        }
        return nil
    }

    private static func make(organization: String, project: String, repository: String) -> AzureReposRemote? {
        guard isValidOrganization(organization), !project.hasPrefix("_"), !repository.isEmpty else { return nil }
        return AzureReposRemote(organization: organization, project: project, repository: repository)
    }
}

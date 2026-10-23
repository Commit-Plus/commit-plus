# azure-repos-remote-recognition Specification

## Purpose

Defines how Commit+ recognizes Azure Repos remote URLs as a single repository identity and uses that identity for web links, browser pull request creation, repository bookmarks, and repository picker filtering.

## Requirements

### Requirement: Azure Repos remote URLs are recognized
Commit+ SHALL recognize these remote forms as Azure Repos: `https://[user@]dev.azure.com/{org}/{project}/_git/{repo}`, `https://{org}.visualstudio.com[/DefaultCollection]/{project}/_git/{repo}`, `git@ssh.dev.azure.com:v3/{org}/{project}/{repo}`, and `{org}@vs-ssh.visualstudio.com:v3/{org}/{project}/{repo}`. Each SHALL resolve to organization, project, and repository.

#### Scenario: HTTPS remote with embedded username
- **WHEN** a repository's remote is `https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp`
- **THEN** it is recognized as Azure Repos with organization `Trantienthanh1998`, project `ChatApp`, and repository `ChatApp`

#### Scenario: SSH remote
- **WHEN** a repository's remote is `git@ssh.dev.azure.com:v3/Trantienthanh1998/ChatApp/ChatApp`
- **THEN** it resolves to the same organization, project, and repository

#### Scenario: Legacy visualstudio.com remote
- **WHEN** a repository's remote is `https://trantienthanh1998.visualstudio.com/DefaultCollection/ChatApp/_git/ChatApp`
- **THEN** it resolves to the same organization, project, and repository

#### Scenario: Not a repository path
- **WHEN** a `dev.azure.com` URL lacks the `_git` segment or has missing components
- **THEN** it is not recognized as an Azure Repos repository

### Requirement: All forms of one Azure repository share an identity
Organization names SHALL compare case-insensitively, percent-encoded components (such as spaces encoded as `%20`) SHALL be decoded for display and re-encoded in generated URLs, and every recognized form of the same repository SHALL produce the same identity and canonical HTTPS URL `https://dev.azure.com/{org}/{project}/_git/{repo}`.

#### Scenario: Names with spaces
- **WHEN** the remote is `https://dev.azure.com/acme/My%20Project/_git/My%20Repo`
- **THEN** the project is shown as `My Project`, the repository as `My Repo`, and generated URLs keep `%20`

#### Scenario: Same repository through different forms
- **WHEN** one clone uses the HTTPS form and another uses the SSH form of the same repository
- **THEN** both are treated as the same repository for bookmarks and preferred-account selection

### Requirement: Azure repositories open in the browser
For an Azure Repos remote, the app SHALL open the repository web page at the canonical URL and the pull request list at `{canonical}/pullrequests`. No issues link SHALL be offered for Azure Repos.

#### Scenario: Open remote in browser
- **WHEN** the user opens an Azure Repos remote in the browser, including an SSH remote
- **THEN** `https://dev.azure.com/{org}/{project}/_git/{repo}` opens

#### Scenario: Bookmark links
- **WHEN** the user views links for an Azure Repos bookmark
- **THEN** a pull requests link is offered and no issues link is offered

### Requirement: Pull requests are created in the browser for Azure Repos
Choosing to open a pull request for a branch whose upstream is an Azure Repos remote SHALL open `{canonical}/pullrequestcreate?sourceRef={branch}` with the branch percent-encoded. In-app pull request listing and creation SHALL report that the provider is not supported, as for other providers without in-app support.

#### Scenario: Create a pull request in the browser
- **WHEN** the user opens a pull request for branch `feature/login` tracking an Azure Repos remote
- **THEN** `https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp/pullrequestcreate?sourceRef=feature%2Flogin` opens

#### Scenario: Unsupported remote message
- **WHEN** the upstream remote is not GitHub, GitLab, Bitbucket, or Azure Repos
- **THEN** the error names all four supported pull request hosts

### Requirement: Azure repositories are bookmarked and filterable
A bookmark created for an Azure Repos remote SHALL use the Azure Repos provider, store its owner path as `{org}/{project}`, and use the canonical HTTPS URL as its remote URL. The repository picker SHALL show an Azure Repos icon for such repositories and offer an "Azure Repos" filter.

#### Scenario: Bookmark an Azure repository
- **WHEN** the user bookmarks a repository whose remote is any recognized Azure Repos form
- **THEN** the bookmark's provider is Azure Repos and its remote URL is the canonical HTTPS URL

#### Scenario: Filter the repository picker
- **WHEN** the user selects the Azure Repos filter in the repository picker
- **THEN** only repositories with Azure Repos remotes are shown

### Requirement: Branch status features degrade for Azure Repos
Features that call provider APIs not implemented for Azure Repos, including branch protection status and merged-branch detection, SHALL treat Azure Repos remotes as unsupported without showing errors.

#### Scenario: Branch protection lookup
- **WHEN** branch protection status is requested for an Azure Repos branch
- **THEN** the status is reported as unsupported and no request is sent

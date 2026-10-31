# Spec Delta

## MODIFIED Requirements

### Requirement: Azure repositories open in the browser
For an Azure Repos remote, the app SHALL open the repository web page at the canonical URL and the pull request list at `{canonical}/pullrequests`. The issues link SHALL open the project's Boards work items page at `https://dev.azure.com/{org}/{project}/_workitems`, because Azure DevOps tracks work items per project rather than per repository.

#### Scenario: Open remote in browser
- **WHEN** the user opens an Azure Repos remote in the browser, including an SSH remote
- **THEN** `https://dev.azure.com/{org}/{project}/_git/{repo}` opens

#### Scenario: Bookmark links
- **WHEN** the user views links for an Azure Repos bookmark
- **THEN** a pull requests link and an issues link are offered

#### Scenario: Issues link opens project work items
- **WHEN** the user opens the issues link for a remote in organization `Trantienthanh1998` and project `ChatApp`
- **THEN** `https://dev.azure.com/Trantienthanh1998/ChatApp/_workitems` opens

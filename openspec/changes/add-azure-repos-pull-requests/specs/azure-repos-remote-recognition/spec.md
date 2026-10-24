## MODIFIED Requirements

### Requirement: Pull requests are created in the browser for Azure Repos
Choosing to open a pull request for a branch whose upstream is an Azure Repos remote SHALL open `{canonical}/pullrequestcreate?sourceRef={branch}` with the branch percent-encoded. In-app pull request features for Azure Repos are defined by the `azure-repos-pull-requests` capability.

#### Scenario: Create a pull request in the browser
- **WHEN** the user opens a pull request for branch `feature/login` tracking an Azure Repos remote
- **THEN** `https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp/pullrequestcreate?sourceRef=feature%2Flogin` opens

#### Scenario: Unsupported remote message
- **WHEN** the upstream remote is not GitHub, GitLab, Bitbucket, or Azure Repos
- **THEN** the error names all four supported pull request hosts

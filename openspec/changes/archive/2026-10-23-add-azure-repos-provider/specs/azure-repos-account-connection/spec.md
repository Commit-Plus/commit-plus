# Spec Delta

## Purpose

Defines how Commit+ connects an Azure DevOps Services organization as an "Azure Repos" provider account with a personal access token or SSH key, uses it as the credential for that organization's Git remotes, and lists its repositories for cloning.

## ADDED Requirements

### Requirement: Azure Repos is offered as a provider
Settings → Connections SHALL offer "Azure Repos" alongside GitHub, GitLab, and Bitbucket when adding an account. Azure Repos SHALL support HTTPS with a personal access token and SSH, and SHALL NOT offer OAuth or a self-hosted server URL.

#### Scenario: Choose Azure Repos when adding an account
- **WHEN** the user opens the add-account sheet and selects Azure Repos
- **THEN** the sheet asks for an organization and offers HTTPS (Personal Access Token) and SSH
- **AND** no OAuth option and no server URL field are shown

### Requirement: Organization input is normalized
The organization field SHALL accept an organization name, `https://dev.azure.com/{org}`, or `https://{org}.visualstudio.com`, and SHALL resolve each to the same organization. Organization names SHALL be compared case-insensitively. Any other input SHALL be rejected before contacting Azure DevOps.

#### Scenario: Paste an organization URL
- **WHEN** the user enters `https://dev.azure.com/Trantienthanh1998/ChatApp` or `trantienthanh1998.visualstudio.com`
- **THEN** the organization resolves to `Trantienthanh1998`

#### Scenario: Invalid organization
- **WHEN** the user enters a value containing spaces or a host other than `dev.azure.com` or `*.visualstudio.com`
- **THEN** the sheet shows an error and no request is sent

### Requirement: PAT connections are validated with Azure DevOps
Connecting over HTTPS SHALL validate the personal access token against the chosen organization before saving. On success the account SHALL show the authenticated user's display name and the organization. An invalid or expired token, or a token without access to the organization, SHALL produce an error and SHALL NOT save the account or token.

#### Scenario: Valid token
- **WHEN** the user enters organization `Trantienthanh1998` and a valid PAT with Code (Read & Write) scope and chooses Connect Account
- **THEN** an Azure Repos account for that organization is saved with status valid
- **AND** the token is stored only in the local Keychain

#### Scenario: Rejected token
- **WHEN** Azure DevOps rejects the token or redirects to a sign-in page
- **THEN** the sheet shows "The personal access token is invalid, expired, or has no access to this organization."
- **AND** nothing is saved

### Requirement: Azure accounts are unique per organization and user
An Azure Repos account SHALL be identified by organization and authenticated user. Connecting the same user to the same organization again SHALL be rejected as already connected; the same user MAY connect several organizations as separate accounts, subject to the existing provider-account plan limit.

#### Scenario: Duplicate connection
- **WHEN** the user connects a PAT for an organization and user that already has an Azure Repos account
- **THEN** the sheet shows that the account is already connected and asks to edit it instead

#### Scenario: Second organization
- **WHEN** a Pro user connects a second organization with the same Microsoft identity
- **THEN** a second Azure Repos account is created

### Requirement: Azure PAT accounts are reconnected by entering a new token
Editing or reconnecting an Azure Repos HTTPS account SHALL require a new personal access token for the same organization and user, validated as on first connection. A token for a different user SHALL be rejected as a different account.

#### Scenario: Replace an expired token
- **WHEN** the user edits an Azure Repos account and enters a new valid PAT for the same user
- **THEN** the stored token is replaced and the account keeps its identity and settings

### Requirement: SSH connections are verified against Azure DevOps
Connecting Azure Repos over SSH SHALL require an organization and a private key, and SHALL verify the key by connecting to `ssh.dev.azure.com`. A key that Azure DevOps rejects SHALL produce an error and SHALL NOT be saved.

#### Scenario: Accepted key
- **WHEN** the user selects an organization and a key registered in Azure DevOps and chooses Test SSH Key
- **THEN** the key is accepted and the account can be saved for that organization

#### Scenario: Rejected key
- **WHEN** Azure DevOps denies the key
- **THEN** the sheet shows the SSH error and the account is not saved

### Requirement: Azure SSH guidance names the accepted key type
When SSH is selected for Azure Repos, the add-account sheet SHALL state that Azure DevOps accepts RSA SSH keys only and that a saved personal access token is kept.

#### Scenario: Choose SSH for Azure Repos
- **WHEN** the user selects the SSH protocol for an Azure Repos account
- **THEN** the sheet states that only RSA keys are accepted and that the saved token stays for switching back to HTTPS

### Requirement: Switching protocols keeps the Azure personal access token
Switching an Azure Repos account between HTTPS and SSH SHALL keep the account's identity and its personal access token on this Mac, so switching back to HTTPS uses the saved token without entering it again. The token SHALL be removed only when the account is disconnected.

#### Scenario: HTTPS to SSH and back
- **WHEN** the user switches an Azure Repos HTTPS account to SSH, saves, and later switches it back to HTTPS and saves
- **THEN** the account keeps its identity and Git operations over HTTPS use the previously saved token

#### Scenario: Saved token is shown when switching back
- **WHEN** the user edits an Azure Repos account with a saved token and selects HTTPS
- **THEN** the sheet states that a personal access token is saved and that entering a new one only replaces it

#### Scenario: SSH-only account switched to HTTPS
- **WHEN** an Azure Repos account connected only over SSH is switched to HTTPS without entering a token
- **THEN** Save stays disabled until a personal access token is connected

### Requirement: Azure accounts supply Git credentials for their organization
For an HTTPS remote recognized as Azure Repos, Git operations SHALL use the PAT of the connected account whose organization matches, regardless of the username embedded in the remote URL or whether the remote uses the `dev.azure.com` or legacy `visualstudio.com` form. For an SSH Azure remote, they SHALL use the matching SSH account's key. Existing preferred-account selection SHALL apply when several accounts match.

#### Scenario: Fetch a private repository
- **WHEN** the user fetches `https://Trantienthanh1998@dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp` with an HTTPS Azure account for that organization connected
- **THEN** the fetch authenticates with that account's PAT without prompting

#### Scenario: Different organization
- **WHEN** the remote belongs to an organization with no connected Azure account
- **THEN** no Azure credential is supplied and Git's normal behavior applies

### Requirement: Azure account repositories can be browsed for cloning
The repository browser SHALL list every enabled repository the Azure account can access across all projects of its organization, named `{project}/{repo}`, with an HTTPS or SSH clone URL matching the account's protocol. Authentication failures SHALL show a reconnect message instead of an empty list.

#### Scenario: Browse repositories
- **WHEN** the user opens the repository browser for an Azure Repos account with access to project `ChatApp`
- **THEN** `ChatApp/ChatApp` is listed and choosing it fills the clone URL `https://dev.azure.com/Trantienthanh1998/ChatApp/_git/ChatApp`

#### Scenario: Disabled repository
- **WHEN** a repository in the organization is disabled
- **THEN** it is not listed

#### Scenario: Token no longer valid
- **WHEN** Azure DevOps rejects the account's token while listing repositories
- **THEN** the browser shows "The personal access token is invalid or expired. Reconnect the account."

### Requirement: Azure account metadata syncs like other providers
Signed-in users' Azure Repos account metadata SHALL sync through the existing provider-account cloud sync. Personal access tokens and SSH keys SHALL remain on the Mac where they were entered, and a synced account on another Mac SHALL show as unavailable on this device until a token or key is entered there.

#### Scenario: Account appears on a second Mac
- **WHEN** the same Commit+ user signs in on another Mac running a version with Azure Repos support
- **THEN** the Azure Repos account is listed with status unavailable on this device

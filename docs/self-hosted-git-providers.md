# Self-hosted Git providers

Commit+ supports configured GitHub Enterprise Server and GitLab Self-Managed installations alongside GitHub.com and GitLab.com.

Connecting or reconnecting self-managed servers requires an active Pro plan. Existing accounts and their stored credentials are retained when a subscription changes.

## Connect an account

1. Open Git provider connections and choose **Add Account**.
2. Select **GitHub** or **GitLab**, then enable **Self-hosted server**.
3. Enter the installation's HTTPS server URL, such as `https://github.company.com` or `https://gitlab.company.com`. GitLab installations may include a port or installation subpath, such as `https://source.company.com:8443/gitlab`.
4. Select **HTTPS**, enter a **Personal Access Token**, and choose **Connect Account**. Commit+ validates the token against the server's user API before storing it in the local Keychain.
5. Choose **Save**. To rotate the token, edit that account and connect with its replacement token.

GitHub tokens need access to the target repositories and permissions for the API actions you use. For a classic token, `repo` covers private repositories; pushing workflow-file changes may require `workflow`. Fine-grained token availability and permissions depend on the Enterprise Server version and administrator policy. GitLab personal access tokens with `api` scope support the integrated API and Git operations. Server policy, token permissions, and repository permissions still govern each operation.

OAuth remains the existing connection method for GitHub.com and GitLab.com. Self-hosted connections use personal access tokens; instance-specific OAuth application setup is not included.

## Work with repositories

In **Clone**, enter the repository's clone URL or expand **Browse connected repositories**, choose an account, and select a repository. The browser loads additional pages with **Load more**. Discovery includes repositories returned by the provider for that token; GitLab discovery uses membership filtering. Fetch, pull, push, remote-branch loading, PR/MR APIs, repository visibility, and branch protection use the configured server and matching credentials.

You can also select **SSH**, choose a private key, and test it against the configured hostname. SSH connectivity uses your SSH configuration, including host aliases and custom SSH ports. An HTTPS API port is not an SSH port. SSH-only accounts do not provide API repository discovery or PR/MR access unless an API token is also retained on that account. When several server installations share one hostname, SSH URLs cannot identify their HTTPS port/subpath unambiguously; use HTTPS or your existing Git/SSH configuration for those remotes. Credentials already configured in Git remain available for repositories without a matching Commit+ account.

## Connection errors

- For unreachable servers or timeouts, check the URL, DNS, network, and company VPN.
- For certificate errors, install and trust your company's certificate using macOS Keychain. Commit+ does not disable HTTPS certificate validation.
- For invalid or expired tokens, edit the account and connect with a replacement token.
- For permission errors, check token scopes, repository access, and your administrator's token/SSO policies. A successful account connection validates identity, not every repository permission.

## Validation status

The implementation has automated regression coverage for server parsing, remote identification, credential isolation, authentication endpoint routing, repository discovery, and API routing. A successful macOS build proves compilation only. Final deployment-specific verification requires private repositories on actual GitHub Enterprise Server and GitLab Self-Managed installations, including clone/fetch/pull/push and PR/MR operations. No minimum server version has been certified against a live installation yet.

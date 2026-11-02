# Changelog

Changes in the latest Commit+ release compared with the previous release.

## v1.1.24

Changes since `v1.1.23`.

### Added

- **SSH key management** — Choose **Configure SSH Keys…** from the Commit+ menu or **Settings → Git** to see the keys in `~/.ssh`, copy a public key for your Git provider, or show it in Finder. Generate a new Ed25519 or RSA 4096 key with an optional passphrase, and use **Add to Keychain…** to load a key into ssh-agent with its passphrase saved in the macOS Keychain, so Git can use it without a Terminal prompt.

### Improved

- The **Actions** menu is now the **Repository** menu, and Git Flow moved into it as a submenu. It adds **New Tag…** (`Cmd+Shift+T`), **Create Pull Request…**, and **Refresh** (`Cmd+R`).
- Settings now has separate **Accounts** and **Profile** sections. Git provider accounts moved from Settings → Git to **Accounts**, and **Profile** holds your Commit+ account, plan, and settings sync. The toolbar account menu is now labeled **Profile**.
- The remote editor rejects a remote name that already exists and a URL another remote already uses, treating URLs that differ only by a trailing slash, a `.git` suffix, or letter case as the same. Long remote lists in Repository Settings now scroll.

### Fixed

- Shift-Return inserts a new line in interactive rebase commit messages and the Repository AI chat box instead of ending editing.

[Compare v1.1.23 to v1.1.24](https://github.com/Commit-Plus/commit-plus/compare/v1.1.23...v1.1.24)

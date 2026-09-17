# Contributing to Commit+

Thank you for your interest in contributing to Commit+! This guide will help you get up and running.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Setting Up Your Development Environment](#setting-up-your-development-environment)
- [Building & Running](#building--running)
- [Running Tests](#running-tests)
- [Project Structure](#project-structure)
- [Coding Conventions](#coding-conventions)
- [Pull Request Process](#pull-request-process)
- [Style Guide](#style-guide)

## Code of Conduct

Be respectful and constructive in all interactions. We are committed to providing a welcoming and inclusive experience for everyone.

## How Can I Contribute?

### Reporting Bugs

- Check [existing issues](https://github.com/Commit-Plus/commit-plus/issues) first to avoid duplicates.
- Open a new issue with a clear title and description.
- Include your macOS version, Commit+ version, and steps to reproduce.

### Suggesting Features

- Open an issue with the **feature request** label.
- Describe the problem you're trying to solve, not just the solution.
- Include mockups or examples if applicable.

### Reporting Security Vulnerabilities

Please **do not** report security vulnerabilities through public issues. See [SECURITY.md](SECURITY.md) for responsible disclosure instructions.

### Submitting Code

- Pick an issue labeled **good first issue** or **help wanted**, or open a discussion for new features.
- Follow the development setup and coding conventions below.
- Submit a pull request with a clear description of your changes.

## Setting Up Your Development Environment

### Prerequisites

| Tool | Version |
|------|---------|
| macOS | 26.2+ |
| Xcode | 26.2+ |
| Git | Any recent version (via Homebrew or Xcode Command Line Tools) |

### Clone the Repository

```bash
git clone https://github.com/Commit-Plus/commit-plus.git
cd macgit
```

### Open in Xcode

```bash
open macgit.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

> **Note:** Xcode places DerivedData under `~/Library/Developer/Xcode/DerivedData/macgit-<hash>/`. The hash is derived from the project path, so each worktree gets its own DerivedData folder.

## Building & Running

### Debug Build (Xcode)

Open `macgit.xcodeproj` in Xcode and press `Cmd+R`.

### Debug Build (Command Line)

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
```

### Release Build

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -configuration Release -destination 'platform=macOS' build
```

## Running Tests

### App Tests

```bash
xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
```

Tests live in `macgitTests/` and create temporary Git repositories to exercise real Git operations.

### CLI Tests

```bash
bash scripts/test-command-line.sh
```

This compiles and runs the CLI integration tests outside of Xcode. It does not launch the app.

> **Tip:** Run tests after non-trivial changes. If the full test suite crashes during bootstrapping ("Early unexpected exit" / `abort() called`), a successful build is sufficient — do not re-run the suite.

## Project Structure

```
macgit/
├── App/                 # App entry point, AppState, toolbar wiring
├── Views/               # SwiftUI views (10 subdirectories by feature area)
├── Services/            # Git operations & business logic
├── Models/              # Data models
├── ViewModels/          # View models
├── Resources/           # Assets

command-line/            # CLI tool source (commit command)
scripts/                 # Build, test, and release automation
macgitTests/             # XCTest test suite
docs/                    # Design specs and implementation plans
functions/               # Firebase Cloud Functions
firebase-tests/          # Firebase security rules tests
```

Git operations are centralized in `macgit/Services/GitStatusService*.swift`.

## Coding Conventions

### License Header

**Every `.swift` file** must include the AGPL v3 license header. Commits missing these markers will be blocked by the pre-commit hook:

```swift
//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
```

The `Copyright (C)` line is recommended but not enforced, so you can add your own name.

### Swift Style

- Use **Swift 5.0** with `async/await` and `actor` for concurrency.
- Follow standard Swift API Design Guidelines.
- Prefer SwiftUI for all UI code.
- Use descriptive naming; avoid abbreviations unless they are widely understood.

### Architecture

- Views should be thin — delegate logic to ViewModels or Services.
- Git operations go through `Services/GitStatusService*.swift`.
- Use `@Observable` or `ObservableObject` for state management as appropriate.

## Pull Request Process

1. **Fork** the repository and create a feature branch from `main`:

   ```bash
   git checkout -b feature/my-feature main
   ```

2. **Make your changes** following the coding conventions above.

3. **Add or update tests** in `macgitTests/` for any non-trivial change.

4. **Build and test** before submitting:

   ```bash
   xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' build
   xcodebuild -project macgit.xcodeproj -scheme macgit -destination 'platform=macOS' test
   ```

5. **Commit** with a clear, descriptive message. Use [Conventional Commits](https://www.conventionalcommits.org/) when possible:

   ```
   feat(stash): add undo support for stash apply
   fix(merge): resolve conflict marker rendering
   docs: update contributing guidelines
   ```

6. **Push** your branch and open a pull request against `main`.

7. In your PR description:
   - Describe **what** changed and **why**.
   - Reference any related issues (e.g., `Closes #42`).
   - Include screenshots or screen recordings for UI changes.

8. **Respond to review feedback.** Maintainers may request changes before merging.

## Style Guide

- **Commits**: imperative mood, lowercase, no period (e.g., "add undo support", not "Added undo support" or "Adds undo support").
- **PR titles**: match commit style.
- **Branches**: use descriptive names like `feature/drag-drop-stash`, `fix/merge-conflict-rendering`.

---

Thank you for contributing to Commit+!

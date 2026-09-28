#!/bin/zsh
set -euo pipefail

# Extract release notes from CHANGELOG.md for a given version.
# Usage: ./scripts/release/extract-release-notes.sh <version> <changelog-path>
# Example: ./scripts/release/extract-release-notes.sh 1.1.7 CHANGELOG.md

VERSION="${1:?usage: extract-release-notes.sh <version> <changelog-path>}"
CHANGELOG="${2:?usage: extract-release-notes.sh <version> <changelog-path>}"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "Changelog not found: $CHANGELOG" >&2
  exit 1
fi

# Read the changelog and extract the section for the given version
# The format is:
# ## v1.1.7
# 
# Changes since `v1.1.6`.
# 
# ### Added
# ...
# [Compare v1.1.6 to v1.1.7](...)

# Use awk to extract the section for the given version
# Start at "## v$VERSION" and stop at the next "## v" or end of file
RELEASE_NOTES=$(awk -v version="v$VERSION" '
  BEGIN { found = 0 }
  /^## / {
    if (found && $0 ~ "^## v") {
      exit
    }
    if ($0 == "## " version) {
      found = 1
      next
    }
  }
  found { print }
' "$CHANGELOG")

if [[ -z "$RELEASE_NOTES" ]]; then
  echo "No release notes found for version v$VERSION in $CHANGELOG" >&2
  exit 1
fi

printf '%s' "$RELEASE_NOTES"
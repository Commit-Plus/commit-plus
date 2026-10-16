#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/commitplus-rebase-tests.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT
swiftc -parse-as-library \
  macgit/Services/Commit.swift \
  macgit/Models/HistoryRebaseAvailability.swift \
  macgit/Models/HistoryRebasePlan.swift \
  macgit/Services/GitStatusService+InteractiveRebase.swift \
  scripts/tests/interactive-rebase.swift \
  -o "$test_directory/rebase-tests"
"$test_directory/rebase-tests"

#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/commitplus-catalog-tests.XXXXXX")
test_binary="$test_directory/catalog-tests"
trap 'rm -rf "$test_directory"' EXIT
swiftc -parse-as-library \
  macgit/Services/LocalDataError.swift \
  macgit/Services/LocalDataTransaction.swift \
  macgit/Services/LocalSQLiteDatabase.swift \
  macgit/Services/LocalDataStore.swift \
  macgit/Models/RepositoryCatalogSnapshot.swift \
  macgit/Services/RepositoryCatalogStore.swift \
  macgit/Services/RecentRepositoriesStore.swift \
  macgit/Models/YourRepository.swift \
  macgit/Services/YourRepositoriesStore.swift \
  macgit/ViewModels/RepositoryDetailModel.swift \
  macgit/Models/RepositoryStatistics.swift \
  macgit/Services/RepositoryStatisticsAggregator.swift \
  macgit/Models/RepositoryBookmark.swift \
  macgit/Models/RepositoryBookmarkRemote.swift \
  macgit/Services/GitStatusService+RepositoryBookmark.swift \
  macgit/Models/RepoPickerStatusSnapshot.swift \
  macgit/Services/GitStatusService+RepositoryDetail.swift \
  scripts/tests/repository-catalog-statistics.swift \
  -o "$test_binary"
"$test_binary"

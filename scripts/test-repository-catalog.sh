#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/commitplus-catalog-tests.XXXXXX")
test_binary="$test_directory/catalog-tests"
trap 'rtk proxy rm -f "$test_binary"; rtk proxy rmdir "$test_directory"' EXIT
rtk proxy swiftc -parse-as-library \
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
rtk proxy "$test_binary"

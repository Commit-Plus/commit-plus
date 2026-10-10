#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 OUTPUT_DIRECTORY REF_COUNT" >&2
  exit 64
fi

fixture_dir=$1
ref_count=$2

if [[ ! $ref_count =~ ^(100|1000|10000)$ ]]; then
  echo "REF_COUNT must be 100, 1000, or 10000." >&2
  exit 64
fi

if [[ -e $fixture_dir ]]; then
  echo "Refusing to overwrite existing path: $fixture_dir" >&2
  exit 73
fi

git init -q "$fixture_dir"
git -C "$fixture_dir" config user.name "Commit+ Sidebar Fixture"
git -C "$fixture_dir" config user.email "fixture@commit.plus"
git -C "$fixture_dir" commit --allow-empty -qm "Initial fixture commit"

commit_hash=$(git -C "$fixture_dir" rev-parse HEAD)
for ((index = 1; index <= ref_count; index++)); do
  printf -v suffix '%05d' "$index"
  git -C "$fixture_dir" update-ref "refs/heads/feature/sidebar/group-$((index % 100))/branch-$suffix" "$commit_hash"
  git -C "$fixture_dir" update-ref "refs/tags/sidebar-$suffix" "$commit_hash"
  git -C "$fixture_dir" update-ref "refs/remotes/origin/perf/branch-$suffix" "$commit_hash"
done

echo "Created sidebar fixture with $ref_count branches, tags, and remote refs at $fixture_dir"

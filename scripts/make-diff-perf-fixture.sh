#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

target=${1:?"usage: $0 <directory>"}
mkdir -p "$target"
cd "$target"
git init -q
git config user.name "Commit+ Diff Fixture"
git config user.email "fixture@example.invalid"

awk 'BEGIN { for (i = 1; i <= 200000; i++) print "baseline " i }' > bulk.txt
awk 'BEGIN { for (i = 1; i <= 100000; i++) print "line " i }' > hunks.txt
printf 'const value = 0;\n' > minified.js
printf '初期値\n' > cjk.txt
printf 'first\r\nsecond\r\n' > crlf.txt
printf 'package main\n\tfunc main() {}\n' > tabs.go
git add .
git commit -qm baseline

awk 'BEGIN { for (i = 1; i <= 200000; i++) print "changed " i }' > bulk.txt
awk 'BEGIN { for (i = 1; i <= 100000; i++) print i % 50 == 0 ? "changed " i : "line " i }' > hunks.txt
awk 'BEGIN { printf "const value=\""; for (i = 0; i < 500000; i++) printf "x"; print "\";" }' > minified.js
awk 'BEGIN { for (i = 0; i < 200000; i++) printf "界"; print "" }' > cjk.txt
printf 'first changed\r\nsecond\r\n' > crlf.txt
printf 'package main\n\tfunc main() {\n\t\tprintln("tabs")\n\t}\n' > tabs.go
printf '%s\n' "$target"

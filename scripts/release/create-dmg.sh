#!/bin/zsh
#  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
#  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

APP_PATH="${1:?usage: create-dmg.sh <app-path> <tag-version>}"
TAG_VERSION="${2:?usage: create-dmg.sh <app-path> <tag-version>}"

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"

test -d "$APP_PATH"

DMG_NAME="Commit+-${TAG_VERSION}-arm64.dmg"
DMG_PATH="$RUNNER_TEMP/$DMG_NAME"
DMG_SOURCE_DIR="$RUNNER_TEMP/CommitPlusDMG"

rm -rf "$DMG_SOURCE_DIR" "$DMG_PATH"
mkdir -p "$DMG_SOURCE_DIR"
ditto "$APP_PATH" "$DMG_SOURCE_DIR/Commit+.app"
ln -s /Applications "$DMG_SOURCE_DIR/Applications"

hdiutil create \
  -volname "Commit+" \
  -srcfolder "$DMG_SOURCE_DIR" \
  -format ULMO \
  -ov \
  "$DMG_PATH"

test -f "$DMG_PATH"
echo "DMG_PATH=$DMG_PATH" >> "$GITHUB_ENV"
echo "DMG_NAME=$DMG_NAME" >> "$GITHUB_ENV"

#!/bin/zsh
set -euo pipefail

TAG_NAME="${1:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast> [release-notes.md]}"
ZIP_NAME="${2:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast> [release-notes.md]}"
ZIP_PATH="${3:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast> [release-notes.md]}"
OUTPUT_APPCAST="${4:?usage: generate-appcast.sh <tag-name> <zip-name> <zip-path> <output-appcast> [release-notes.md]}"
# Optional Markdown release notes, embedded so Sparkle's update alert can show them.
RELEASE_NOTES_PATH="${5:-}"

: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${SPARKLE_ED25519_PRIVATE_KEY:?SPARKLE_ED25519_PRIVATE_KEY is required}"

GENERATE_APPCAST="$RUNNER_TEMP/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
APPCAST_WORK_DIR="$RUNNER_TEMP/appcast-work"
PRIVATE_KEY_PATH="$RUNNER_TEMP/sparkle_private_ed25519.pem"
DOWNLOAD_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/${TAG_NAME}/"

if [[ ! -x "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast binary was not found at: $GENERATE_APPCAST" >&2
  echo "Available Sparkle artifacts:" >&2
  find "$RUNNER_TEMP/SourcePackages/artifacts" -maxdepth 5 -type f -name generate_appcast -print >&2 2>/dev/null || true
  exit 1
fi

rm -rf "$APPCAST_WORK_DIR"
mkdir -p "$APPCAST_WORK_DIR"

cp "$ZIP_PATH" "$APPCAST_WORK_DIR/$ZIP_NAME"
if [[ -n "$RELEASE_NOTES_PATH" ]]; then
  if [[ ! -s "$RELEASE_NOTES_PATH" ]]; then
    echo "Release notes file is missing or empty: $RELEASE_NOTES_PATH" >&2
    exit 1
  fi
  # generate_appcast picks up release notes that share the archive's basename.
  cp "$RELEASE_NOTES_PATH" "$APPCAST_WORK_DIR/${ZIP_NAME%.*}.md"
fi
printf '%s\n' "$SPARKLE_ED25519_PRIVATE_KEY" > "$PRIVATE_KEY_PATH"

"$GENERATE_APPCAST" \
  --ed-key-file "$PRIVATE_KEY_PATH" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --embed-release-notes \
  -o "$OUTPUT_APPCAST" \
  "$APPCAST_WORK_DIR"

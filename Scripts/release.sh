#!/bin/bash
# Publishes a release: sets the version, builds, zips the app and creates the GitHub release
# that the in-app updater reads (asset name must stay Dustbuster.zip).
# Usage: Scripts/release.sh 1.2.0 "Release notes"
set -euo pipefail

VERSION="${1:?Usage: Scripts/release.sh <version> [notes]}"
NOTES="${2:-Dustbuster $VERSION}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit or stash your changes first: the release is tagged on the current commit." >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" Resources/Info.plist

Scripts/build_app.sh
rm -f .build/Dustbuster.zip
ditto -c -k --keepParent .build/Dustbuster.app .build/Dustbuster.zip

git add Resources/Info.plist
git commit -m "Release $VERSION" || true
git tag "v$VERSION"
git push
git push origin "v$VERSION"
gh release create "v$VERSION" .build/Dustbuster.zip --title "Dustbuster $VERSION" --notes "$NOTES"
echo "==> Released v$VERSION"

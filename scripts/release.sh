#!/bin/sh
# Publishes the version in VERSION as a GitHub release with a notarized Toma.dmg.
# Run on the Mac that holds the Developer ID certificate and the notarytool profile, from main.
# The website downloads releases/latest/download/Toma.dmg, so it serves the new version as soon
# as this finishes. Needs the gh CLI, logged in with write access.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
TAG="v$VERSION"
REPOSITORY=eherrerosj/toma
GH=./scripts/github.sh
[ "$($GH api user --jq .login)" = eherrerosj ] || { echo 'Use the eherrerosj account.' >&2; exit 1; }
SIGNER=$(REQUIRE_NOTARIZATION=1 python3 scripts/signing.py resolve)
read -r SIGNING_IDENTITY SIGNING_TEAM SIGNING_KIND <<EOF_SIGNER
$SIGNER
EOF_SIGNER
export SIGNING_IDENTITY SIGNING_TEAM

[ "$(git branch --show-current)" = main ] || { echo "Run from main."; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Uncommitted changes."; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "main differs from origin/main."; exit 1; }
BUILD_SHA=$(git rev-parse HEAD)
if git rev-parse "refs/tags/$TAG^{commit}" >/dev/null 2>&1; then
  [ "$(git rev-parse "refs/tags/$TAG^{commit}")" = "$BUILD_SHA" ] || { echo 'The version tag names a different commit. Bump VERSION.' >&2; exit 1; }
fi
if $GH release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then echo "$TAG already exists. Bump VERSION."; exit 1; fi

NOTES=$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found { print }' CHANGELOG.md)
[ -n "$NOTES" ] || { echo "CHANGELOG.md has no [$VERSION] section."; exit 1; }

BUILD_COMMIT_SHA="$BUILD_SHA" REQUIRE_NOTARIZATION=1 ./build.sh dmg
[ "$(git rev-parse HEAD)" = "$BUILD_SHA" ] || { echo 'HEAD changed during the build.' >&2; exit 1; }
[ "$(plutil -extract TomaBuildCommit raw -o - 'Toma Personal.app/Contents/Info.plist')" = "$BUILD_SHA" ] || { echo 'The app has a different build commit.' >&2; exit 1; }
# A DMG that is not notarized would fail Gatekeeper for every visitor: never publish one.
xcrun stapler validate Toma.dmg

NOTES_FILE=$(mktemp -t toma-release-notes)
trap 'rm -f "$NOTES_FILE"' EXIT HUP INT TERM
printf '%s\n' "$NOTES" > "$NOTES_FILE"
$GH release create "$TAG" Toma.dmg --repo "$REPOSITORY" --target "$BUILD_SHA" --title "Toma Personal $VERSION" --notes-file "$NOTES_FILE"
echo "Publicado: $TAG"

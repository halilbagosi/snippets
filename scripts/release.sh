#!/bin/bash
# Builds a Developer ID-signed, notarized and stapled Snippets.dmg.
#
#   scripts/release.sh                      # build/release/Snippets.dmg
#   scripts/release.sh --upload owner/repo  # ...and attach it to a GitHub prerelease
#
# One-time setup:
#   - Xcode ▸ Settings ▸ Accounts signed in to team KCH5545G6F (export creates
#     the Developer ID certificate if there is none).
#   - Notary credentials in the keychain, with an app-specific password:
#       xcrun notarytool store-credentials snippets-notary \
#         --apple-id <apple-id> --team-id KCH5545G6F
#
# Env: NOTARY_PROFILE (default snippets-notary), BUILD_NUMBER (default: the
# commit count, so every release from a newer commit sorts higher).
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

UPLOAD_REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upload) UPLOAD_REPO="${2:?--upload needs owner/repo}"; shift 2 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 64 ;;
    esac
done

NOTARY_PROFILE="${NOTARY_PROFILE:-snippets-notary}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
OUT=build/release
ARCHIVE="$OUT/Snippets.xcarchive"
APP="$OUT/export/Snippets.app"
DMG="$OUT/Snippets.dmg"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "warning: working tree has uncommitted changes; they will be in this build" >&2
fi

# Fail before a multi-minute build, not after it.
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null || {
    echo "error: no notary credentials in keychain profile '$NOTARY_PROFILE' (see the setup notes in $0)" >&2
    exit 1
}

rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Archiving (build $BUILD_NUMBER)"
xcodebuild archive \
    -project Snippets.xcodeproj -scheme Snippets -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -allowProvisioningUpdates \
    -quiet

codesign --verify --deep --strict "$APP"
# Captured first: `codesign | grep -q` fails under pipefail when grep exits
# early and codesign takes the SIGPIPE.
SIGNATURE=$(codesign -d --verbose=2 "$APP" 2>&1)
grep -q "Authority=Developer ID Application" <<<"$SIGNATURE" || {
    echo "error: $APP is not signed with a Developer ID certificate" >&2
    exit 1
}
grep -q "flags=.*runtime" <<<"$SIGNATURE" || {
    echo "error: $APP was signed without the hardened runtime" >&2
    exit 1
}

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")

echo "==> Building DMG"
STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Snippets -srcfolder "$STAGING" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

# A cloud-managed certificate has no local private key; the DMG can go
# unsigned then, since notarization covers the app inside it.
DMG_IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*(KCH5545G6F)\)"/\1/p' || true)
DMG_IDENTITY="${DMG_IDENTITY%%$'\n'*}"
if [[ -n "$DMG_IDENTITY" ]]; then
    codesign --sign "$DMG_IDENTITY" --timestamp "$DMG"
fi

echo "==> Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format json > "$OUT/notary.json" || true
STATUS=$(/usr/bin/plutil -extract status raw "$OUT/notary.json" 2>/dev/null || echo "unknown")
if [[ "$STATUS" != "Accepted" ]]; then
    echo "error: notarization status: $STATUS" >&2
    ID=$(/usr/bin/plutil -extract id raw "$OUT/notary.json" 2>/dev/null || true)
    [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2
    exit 1
fi

xcrun stapler staple -q "$DMG"
xcrun stapler validate -q "$DMG"
# Gatekeeper's verdict on the app as a tester will get it: inside the DMG.
MOUNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT
spctl --assess --type execute --verbose=2 "$MOUNT/Snippets.app"
hdiutil detach "$MOUNT" -quiet
trap - EXIT

echo "==> $DMG — Snippets $VERSION ($BUILD_NUMBER)"

if [[ -n "$UPLOAD_REPO" ]]; then
    TAG="v$VERSION-beta.$BUILD_NUMBER"
    echo "==> Publishing $TAG to $UPLOAD_REPO"
    gh release create "$TAG" "$DMG" --repo "$UPLOAD_REPO" --prerelease \
        --title "Snippets $VERSION beta ($BUILD_NUMBER)" --notes "Test build from $(git rev-parse --short HEAD)."
fi

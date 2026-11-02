#!/bin/bash
# Builds a Developer ID-signed, notarized and stapled Snippets.dmg.
#
#   scripts/release.sh                      # build/release/Snippets.dmg
#   scripts/release.sh --upload owner/repo  # ...and attach it to a GitHub prerelease
#   scripts/release.sh --upload owner/repo --final notes.html
#                                           # ...as a full release, added to
#                                           # site/appcast.xml for in-app updates
#
# One-time setup:
#   - Xcode ▸ Settings ▸ Accounts signed in to team KCH5545G6F (export creates
#     the Developer ID certificate if there is none).
#   - Notary credentials in the keychain, with an app-specific password:
#       xcrun notarytool store-credentials snippets-notary \
#         --apple-id <apple-id> --team-id KCH5545G6F
#   - dmgbuild, which lays out the DMG window:
#       python3 -m pip install --user dmgbuild
#   - The Sparkle EdDSA key in the login keychain (generate_keys; see README).
#
# Env: NOTARY_PROFILE (default snippets-notary), BUILD_NUMBER (default: the
# commit count, so every release from a newer commit sorts higher).
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

UPLOAD_REPO=""
FINAL_NOTES=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upload) UPLOAD_REPO="${2:?--upload needs owner/repo}"; shift 2 ;;
        --final) FINAL_NOTES="${2:?--final needs a release-notes HTML file}"; shift 2 ;;
        -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
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

# Accept a clone URL too: gh wants owner/repo, and reports a misleading
# "workflow scope" error for a name it can't resolve.
UPLOAD_REPO="${UPLOAD_REPO#https://github.com/}"
UPLOAD_REPO="${UPLOAD_REPO#git@github.com:}"
UPLOAD_REPO="${UPLOAD_REPO%.git}"

# Fail before a multi-minute build, not after it.
python3 -c "import dmgbuild" 2>/dev/null || {
    echo "error: dmgbuild is missing; install it with: python3 -m pip install --user dmgbuild" >&2
    exit 1
}
if [[ -n "$UPLOAD_REPO" ]]; then
    gh repo view "$UPLOAD_REPO" --json name >/dev/null || {
        echo "error: can't reach GitHub repo '$UPLOAD_REPO' (expected owner/repo)" >&2
        exit 1
    }
fi
PACKAGES=build/packages
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"
if [[ -n "$FINAL_NOTES" ]]; then
    [[ -n "$UPLOAD_REPO" ]] || { echo "error: --final needs --upload owner/repo" >&2; exit 64; }
    [[ -f "$FINAL_NOTES" ]] || { echo "error: no release notes at $FINAL_NOTES" >&2; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || {
        echo "error: a final release must be built from a clean tree" >&2
        exit 1
    }
    security find-generic-password -s "https://sparkle-project.org" -a ed25519 >/dev/null 2>&1 || {
        echo "error: no Sparkle signing key in the keychain (run generate_keys; see README)" >&2
        exit 1
    }
    MARKETING_VERSION=$(xcodebuild -project Snippets.xcodeproj -scheme Snippets -configuration Release \
        -showBuildSettings 2>/dev/null | sed -n 's/^ *MARKETING_VERSION = //p' | head -1)
    [[ -n "$MARKETING_VERSION" ]] || { echo "error: couldn't read MARKETING_VERSION" >&2; exit 1; }
    # A build number the feed would refuse is cheaper to find now than after the archive.
    python3 scripts/appcast.py --appcast site/appcast.xml --build "$BUILD_NUMBER" --check
    if gh release view "v$MARKETING_VERSION" --repo "$UPLOAD_REPO" >/dev/null 2>&1; then
        echo "error: v$MARKETING_VERSION is already released; bump MARKETING_VERSION first" >&2
        exit 1
    fi
fi
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
    -clonedSourcePackagesDirPath "$PACKAGES" \
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
# Window layout and background: scripts/dmg/ (render-background.swift draws it).
python3 -m dmgbuild -s scripts/dmg/settings.py \
    -D app="$APP" -D background=scripts/dmg/background.png \
    Snippets "$DMG" 2>&1 | grep -v "is deprecated" || true
[[ -f "$DMG" ]] || { echo "error: dmgbuild didn't produce $DMG" >&2; exit 1; }

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

if [[ -n "$FINAL_NOTES" ]]; then
    TAG="v$VERSION"
    # sign_update prints: sparkle:edSignature="…" length="…"
    SIGNED=$("$SPARKLE_BIN/sign_update" "$DMG")
    SIGNATURE=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' <<<"$SIGNED")
    LENGTH=$(sed -n 's/.*length="\([0-9]*\)".*/\1/p' <<<"$SIGNED")
    [[ -n "$SIGNATURE" && -n "$LENGTH" ]] || { echo "error: sign_update gave: $SIGNED" >&2; exit 1; }

    # Feed first: if it fails, nothing public exists yet and a rerun isn't blocked.
    python3 scripts/appcast.py --appcast site/appcast.xml \
        --version "$VERSION" --build "$BUILD_NUMBER" \
        --url "https://github.com/$UPLOAD_REPO/releases/download/$TAG/Snippets.dmg" \
        --length "$LENGTH" --signature "$SIGNATURE" --min-system 26.0 \
        --notes-file "$FINAL_NOTES"

    echo "==> Publishing $TAG to $UPLOAD_REPO"
    if ! gh release create "$TAG" "$DMG" --repo "$UPLOAD_REPO" --latest \
        --title "Snippets $VERSION" --notes-file "$FINAL_NOTES"; then
        git checkout -- site/appcast.xml
        echo "error: release not published; site/appcast.xml restored" >&2
        exit 1
    fi
    echo "==> site/appcast.xml now offers $VERSION ($BUILD_NUMBER)."
    echo "    Commit it and publish site/ to the Pages repo; installed copies see it on their next check."
elif [[ -n "$UPLOAD_REPO" ]]; then
    TAG="v$VERSION-beta.$BUILD_NUMBER"
    echo "==> Publishing $TAG to $UPLOAD_REPO"
    gh release create "$TAG" "$DMG" --repo "$UPLOAD_REPO" --prerelease \
        --title "Snippets $VERSION beta ($BUILD_NUMBER)" --notes "Test build from $(git rev-parse --short HEAD)."
fi

#!/bin/bash
#
# Builds a signed CharmDrop.app and wraps it in a drag-to-Applications DMG.
#
# Usage:
#   Scripts/build-dmg.sh                         Release, native architecture
#   Scripts/build-dmg.sh --universal             Release, arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: …" \
#     Scripts/build-dmg.sh --universal
#
# The DMG is written to build/CharmDrop-<version>.dmg
# Notarization is optional and only runs when NOTARY_PROFILE is set.
#   NOTARY_PROFILE="charmdrop-notary" Scripts/build-dmg.sh --universal

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="${APP_NAME:-CharmDrop}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

BUILD_APP_ARGS=(--release)
for argument in "$@"; do
	case "$argument" in
		--universal|--release|--debug) BUILD_APP_ARGS+=("$argument") ;;
		*)
			echo "Unknown argument: $argument" >&2
			echo "Usage: Scripts/build-dmg.sh [--universal]" >&2
			exit 64
			;;
	esac
done

OUTPUT_DIR="$REPO_ROOT/build"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$MARKETING_VERSION.dmg"
STAGING="$OUTPUT_DIR/dmg-staging"
VOLUME_NAME="$APP_NAME"

echo "==> Building $APP_NAME.app"
"$REPO_ROOT/Scripts/build-app.sh" "${BUILD_APP_ARGS[@]}"

if [[ ! -d "$APP_BUNDLE" ]]; then
	echo "Expected app bundle at $APP_BUNDLE" >&2
	exit 1
fi

echo "==> Staging DMG contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
# ditto preserves resource forks and code-signature integrity better than cp -R.
ditto "$APP_BUNDLE" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG_PATH"
rm -f "$DMG_PATH"
hdiutil create \
	-volname "$VOLUME_NAME" \
	-srcfolder "$STAGING" \
	-ov -format UDZO \
	-fs HFS+ \
	"$DMG_PATH" >/dev/null

rm -rf "$STAGING"

echo "==> Signing DMG with identity: $SIGN_IDENTITY"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
	codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
else
	codesign --force --timestamp=none --sign - "$DMG_PATH"
fi
codesign --verify --verbose=1 "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
	if [[ "$SIGN_IDENTITY" == "-" ]]; then
		echo "NOTARY_PROFILE is set but SIGN_IDENTITY is ad-hoc; notarization will fail." >&2
		exit 1
	fi
	echo "==> Submitting to Apple notary service"
	xcrun notarytool submit "$DMG_PATH" \
		--keychain-profile "$NOTARY_PROFILE" \
		--wait
	echo "==> Stapling notarization ticket"
	xcrun stapler staple "$DMG_PATH"
	xcrun stapler validate "$DMG_PATH"
fi

echo ""
echo "DMG:  $DMG_PATH"
ls -lh "$DMG_PATH"
echo ""
if [[ "$SIGN_IDENTITY" == "-" ]]; then
	echo "Signed ad-hoc. This image runs on this Mac; customers will see a"
	echo "Gatekeeper warning until you rebuild with a Developer ID identity"
	echo "and notarize (see DISTRIBUTION.md)."
else
	echo "Signed with: $SIGN_IDENTITY"
	if [[ -z "$NOTARY_PROFILE" ]]; then
		echo "Not notarized. Customers still need a stapled Developer ID"
		echo "build — set NOTARY_PROFILE and a Developer ID SIGN_IDENTITY."
	fi
fi

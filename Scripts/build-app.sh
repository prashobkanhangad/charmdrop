#!/bin/bash
#
# Assembles a runnable .app bundle around the SwiftPM executable.
#
# SwiftPM produces a bare Mach-O binary, but a menu bar app needs a real bundle:
# MenuBarExtra, LSUIElement, the Settings scene, URL scheme registration and
# window levels all depend on Info.plist and a bundle identity.
#
# Usage:
#   Scripts/build-app.sh                  Debug build, native architecture
#   Scripts/build-app.sh --release        Release build, native architecture
#   Scripts/build-app.sh --release --universal
#                                         Release build, arm64 + x86_64
#
# Signing: the bundle is ad-hoc signed so it runs locally. For distribution use
# a Developer ID identity instead — see DISTRIBUTION.md.
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#     Scripts/build-app.sh --release

set -euo pipefail

# ------------------------------------------------------------------ configure
# CHANGE ME for your own product.
APP_NAME="CharmDrop"
BUNDLE_ID="${BUNDLE_ID:-com.company.charmdrop}"
URL_SCHEME="${URL_SCHEME:-charmdrop}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
COPYRIGHT="${COPYRIGHT:-Copyright (c) $(date +%Y). All rights reserved.}"

# Ad-hoc ("-") unless a real identity is supplied.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# ----------------------------------------------------------------- arguments
CONFIGURATION="debug"
# Bash 3.2 (the macOS system bash) errors on expanding an empty array under
# `set -u`, so the array is expanded through this guard everywhere.
BUILD_FLAGS=()

for argument in "$@"; do
	case "$argument" in
		--release) CONFIGURATION="release" ;;
		--debug) CONFIGURATION="debug" ;;
		--universal) BUILD_FLAGS+=(--arch arm64 --arch x86_64) ;;
		*)
			echo "Unknown argument: $argument" >&2
			exit 64
			;;
	esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUTPUT_DIR="$REPO_ROOT/build"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"

# --------------------------------------------------------------------- build
echo "==> Building ($CONFIGURATION)"
swift build -c "$CONFIGURATION" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"}

BINARY_PATH="$(swift build -c "$CONFIGURATION" ${BUILD_FLAGS[@]+"${BUILD_FLAGS[@]}"} --show-bin-path)/$APP_NAME"
if [[ ! -f "$BINARY_PATH" ]]; then
	echo "Build product not found at $BINARY_PATH" >&2
	exit 1
fi

# ------------------------------------------------------------------ assemble
echo "==> Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY_PATH" "$CONTENTS/MacOS/$APP_NAME"

ICON_SOURCE="$REPO_ROOT/Resources/AppIcon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
	cp "$ICON_SOURCE" "$CONTENTS/Resources/AppIcon.icns"
else
	echo "warning: missing $ICON_SOURCE — Finder will show the generic app icon" >&2
fi

# Classic bundle marker. Harmless, and some tooling still looks for it.
printf 'APPL????' > "$CONTENTS/PkgInfo"

sed \
	-e "s|__APP_NAME__|$APP_NAME|g" \
	-e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
	-e "s|__URL_SCHEME__|$URL_SCHEME|g" \
	-e "s|__MARKETING_VERSION__|$MARKETING_VERSION|g" \
	-e "s|__BUILD_VERSION__|$BUILD_VERSION|g" \
	-e "s|__COPYRIGHT__|$COPYRIGHT|g" \
	"$REPO_ROOT/Scripts/Info.plist.template" > "$CONTENTS/Info.plist"

# Copy any SwiftPM-generated resource bundles (present once real charm art or
# sounds are added to the target).
BIN_DIR="$(dirname "$BINARY_PATH")"
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
	cp -R "$bundle" "$CONTENTS/Resources/"
done
shopt -u nullglob

# --------------------------------------------------------------------- sign
echo "==> Signing with identity: $SIGN_IDENTITY"
CODESIGN_FLAGS=(--force --timestamp=none --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
	# Real distribution builds want a secure timestamp; notarization requires it.
	CODESIGN_FLAGS=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
fi

codesign "${CODESIGN_FLAGS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Run:   open \"$APP_BUNDLE\""

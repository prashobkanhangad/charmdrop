#!/bin/bash
# Regenerates Resources/AppIcon.icns from Scripts/generate-app-icon.swift
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cp "$REPO_ROOT/Scripts/generate-app-icon.swift" "$WORKDIR/main.swift"
swiftc -O "$WORKDIR/main.swift" -o "$WORKDIR/generate-app-icon"
"$WORKDIR/generate-app-icon" "$REPO_ROOT"

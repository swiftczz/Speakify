#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f Sources/Speakify/Resources/AppIcon.icns ]]; then
  swift Scripts/generate-icon.swift
fi

swift build -c release --scratch-path build

APP_DIR="$ROOT_DIR/build/release/Speakify.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/build/release/Speakify" "$MACOS_DIR/Speakify"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Sources/Speakify/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

rm -rf "$ROOT_DIR/.build"

echo "$APP_DIR"

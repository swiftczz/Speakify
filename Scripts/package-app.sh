#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CLEAN_BUILD=false
SIGN_APP=true
NOTARIZE_APP=false

for argument in "$@"; do
  case "$argument" in
    --clean)
      CLEAN_BUILD=true
      ;;
    --unsigned)
      SIGN_APP=false
      ;;
    --notarize)
      NOTARIZE_APP=true
      ;;
    --help)
      echo "Usage: Scripts/package-app.sh [--clean] [--unsigned] [--notarize]"
      exit 0
      ;;
    *)
      echo "Unknown option: $argument" >&2
      exit 2
      ;;
  esac
done

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
for localization_directory in "$ROOT_DIR"/Sources/SpeakifyApp/Resources/*.lproj; do
  cp -R "$localization_directory" "$RESOURCES_DIR/"
done

VERSION="${SPEAKIFY_VERSION:-0.1.0}"
BUILD_NUMBER="${SPEAKIFY_BUILD_NUMBER:-1}"
BUNDLE_ID="${SPEAKIFY_BUNDLE_ID:-com.local.Speakify}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"

if [[ "$SIGN_APP" == true ]]; then
  SIGNING_IDENTITY="${SPEAKIFY_SIGNING_IDENTITY:--}"
  codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
fi

if [[ "$NOTARIZE_APP" == true ]]; then
  if [[ "$SIGN_APP" != true || "${SPEAKIFY_SIGNING_IDENTITY:--}" == "-" ]]; then
    echo "--notarize requires a Developer ID identity in SPEAKIFY_SIGNING_IDENTITY." >&2
    exit 2
  fi
  if [[ -z "${SPEAKIFY_NOTARY_PROFILE:-}" ]]; then
    echo "--notarize requires SPEAKIFY_NOTARY_PROFILE." >&2
    exit 2
  fi

  ARCHIVE_PATH="$ROOT_DIR/build/release/Speakify.zip"
  ditto -c -k --keepParent "$APP_DIR" "$ARCHIVE_PATH"
  xcrun notarytool submit "$ARCHIVE_PATH" \
    --keychain-profile "$SPEAKIFY_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_DIR"
fi

# The release build uses its own scratch path (build/), so .build/ here only holds
# the debug and test artifacts. Removing it made every following `swift test` a cold
# build; pass --clean to opt into that.
if [[ "$CLEAN_BUILD" == true ]]; then
  rm -rf "$ROOT_DIR/.build"
fi

echo "$APP_DIR"

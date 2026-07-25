#!/usr/bin/env bash
set -euo pipefail

# Packages the Speakify executable into a signed .app, and optionally a DMG.
# Structure mirrors DeepListen's build_and_run.sh (version resolved from the git
# tag, per-arch builds, drag-to-install DMG), adapted to Speakify's conventions:
# a checked-in Support/Info.plist stamped in place, bundled .lproj localizations,
# an optional notarization step, and the no-argument "signed release app" call
# that CI depends on.

APP_NAME="Speakify"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$ROOT_DIR/build/release/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_SOURCE="$ROOT_DIR/Support/Info.plist"
ICON_SOURCE="$ROOT_DIR/Support/AppIcon.icns"

# Version priority: SPEAKIFY_VERSION > most recent git tag (without the v
# prefix) > 0.0.0-dev.
if [[ -z "${SPEAKIFY_VERSION:-}" ]]; then
  if tag=$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null); then
    SPEAKIFY_VERSION="${tag#v}"
  else
    SPEAKIFY_VERSION="0.0.0-dev"
  fi
fi
BUILD_NUMBER="${SPEAKIFY_BUILD_NUMBER:-1}"
BUNDLE_ID="${SPEAKIFY_BUNDLE_ID:-com.local.Speakify}"

CLEAN_BUILD=false
SIGN_APP=true
NOTARIZE_APP=false
MAKE_DMG=false
# Debug builds exist so the development loop still produces a real .app. A bare
# `swift run` binary is not a bundle, so it has no Contents/Resources: the language
# picker silently does nothing, and Settings, Now Playing and the media keys are all
# degraded. Building the bundle is the only way to exercise what ships.
CONFIGURATION="release"
# Empty means a native single-arch release build, matching the historical
# default that CI and the README rely on.
ARCH=""

usage() {
  echo "Usage: script/build_and_run.sh [--debug] [--arch <universal|arm64|x86_64>] [--dmg] [--unsigned] [--notarize] [--clean]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="${2:-}"
      shift
      ;;
    --arch=*)
      ARCH="${1#--arch=}"
      ;;
    --debug)    CONFIGURATION="debug" ;;
    --dmg)      MAKE_DMG=true ;;
    --unsigned) SIGN_APP=false ;;
    --notarize) NOTARIZE_APP=true ;;
    --clean)    CLEAN_BUILD=true ;;
    --help)     usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

case "$ARCH" in
  ""|universal|arm64|x86_64) ;;
  *)
    echo "Unknown --arch: $ARCH (expected universal, arm64 or x86_64)" >&2
    exit 2
    ;;
esac

# One argument vector drives both the build and the bin-path lookup, so the
# packaged binary always comes from exactly what we just compiled.
build_binary() {
  local build_args=(-c "$CONFIGURATION" --scratch-path build)
  case "$ARCH" in
    universal) build_args+=(--arch arm64 --arch x86_64) ;;
    arm64)     build_args+=(--arch arm64) ;;
    x86_64)    build_args+=(--arch x86_64) ;;
  esac

  echo "==> Building ${ARCH:-native} $CONFIGURATION (version $SPEAKIFY_VERSION)" >&2
  swift build "${build_args[@]}" >&2
  echo "$(swift build --show-bin-path "${build_args[@]}")/$APP_NAME"
}

package_app_from_binary() {
  local binary="$1"
  rm -rf "$APP_DIR"
  mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

  cp "$binary" "$MACOS_DIR/$APP_NAME"
  chmod +x "$MACOS_DIR/$APP_NAME"
  cp "$INFO_PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"

  if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
  fi
  for localization_directory in "$ROOT_DIR"/Sources/Speakify/Resources/*.lproj; do
    cp -R "$localization_directory" "$RESOURCES_DIR/"
  done

  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SPEAKIFY_VERSION" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$CONTENTS_DIR/Info.plist"
}

sign_app() {
  local identity="${SPEAKIFY_SIGNING_IDENTITY:--}"
  echo "==> Signing ($identity)" >&2
  codesign --force --deep --options runtime --sign "$identity" "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
}

notarize_app() {
  if [[ "$SIGN_APP" != true || "${SPEAKIFY_SIGNING_IDENTITY:--}" == "-" ]]; then
    echo "--notarize requires a Developer ID identity in SPEAKIFY_SIGNING_IDENTITY." >&2
    exit 2
  fi
  if [[ -z "${SPEAKIFY_NOTARY_PROFILE:-}" ]]; then
    echo "--notarize requires SPEAKIFY_NOTARY_PROFILE." >&2
    exit 2
  fi

  local archive_path="$ROOT_DIR/build/release/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP_DIR" "$archive_path"
  xcrun notarytool submit "$archive_path" \
    --keychain-profile "$SPEAKIFY_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_DIR"
}

create_dmg() {
  mkdir -p "$DIST_DIR"
  local arch_label="${ARCH:-native}"
  local dmg_path="$DIST_DIR/${APP_NAME}-${arch_label}-${SPEAKIFY_VERSION}.dmg"
  rm -f "$dmg_path"

  # Staging holds the app plus an /Applications symlink so the mounted volume
  # supports drag-to-install.
  local staging_dir
  staging_dir="$(mktemp -d)"
  trap 'rm -rf "${staging_dir:-}"' RETURN
  cp -R "$APP_DIR" "$staging_dir/"
  ln -s /Applications "$staging_dir/Applications"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$staging_dir" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$dmg_path" >/dev/null

  trap - RETURN
  rm -rf "$staging_dir"
  echo "$dmg_path"
}

if [[ ! -f "$ICON_SOURCE" ]]; then
  swift script/generate-icon.swift
fi

BINARY="$(build_binary)"
package_app_from_binary "$BINARY"

if [[ "$SIGN_APP" == true ]]; then
  sign_app
fi

if [[ "$NOTARIZE_APP" == true ]]; then
  notarize_app
fi

if [[ "$MAKE_DMG" == true ]]; then
  echo "==> Creating DMG" >&2
  create_dmg
fi

# The release build uses its own scratch path (build/), so .build/ here only holds
# the debug and test artifacts. Removing it made every following `swift test` a cold
# build; pass --clean to opt into that.
if [[ "$CLEAN_BUILD" == true ]]; then
  rm -rf "$ROOT_DIR/.build"
fi

echo "$APP_DIR"

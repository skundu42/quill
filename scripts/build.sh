#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
SIGNING_IDENTITY=${QUILL_SIGNING_IDENTITY:-}

if [ -z "$SIGNING_IDENTITY" ]; then
  SIGNING_IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1)
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  echo "Error: no Developer ID Application signing identity found" >&2
  echo "Set QUILL_SIGNING_IDENTITY to a valid signing identity." >&2
  exit 1
fi

cd "$ROOT_DIR"
xcodegen generate
xcodebuild \
  -project Quill.xcodeproj \
  -scheme Quill \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

mkdir -p "$DIST_DIR"
ditto "$DERIVED_DATA/Build/Products/Release/Quill.app" "$DIST_DIR/Quill.app"

if [ -n "${QUILL_MARKETING_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleShortVersionString $QUILL_MARKETING_VERSION" \
    "$DIST_DIR/Quill.app/Contents/Info.plist"
fi

if [ -n "${QUILL_BUILD_NUMBER:-}" ]; then
  /usr/libexec/PlistBuddy \
    -c "Set :CFBundleVersion $QUILL_BUILD_NUMBER" \
    "$DIST_DIR/Quill.app/Contents/Info.plist"
fi

MICROPHONE_USAGE_DESCRIPTION=$(/usr/libexec/PlistBuddy \
  -c "Print :NSMicrophoneUsageDescription" \
  "$DIST_DIR/Quill.app/Contents/Info.plist" 2>/dev/null || true)
if [ -z "$MICROPHONE_USAGE_DESCRIPTION" ]; then
  echo "Error: built app is missing NSMicrophoneUsageDescription" >&2
  exit 1
fi

codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "$ROOT_DIR/Quill/Resources/Quill.entitlements" \
  "$DIST_DIR/Quill.app"

# Xcode registers its intermediate build with Launch Services. Remove that
# duplicate identity so macOS resolves Quill to the installed application.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
"$LSREGISTER" -u "$DERIVED_DATA/Build/Products/Release/Quill.app" 2>/dev/null || true

echo "Built $DIST_DIR/Quill.app"

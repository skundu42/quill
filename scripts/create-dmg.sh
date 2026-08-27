#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 /path/to/Quill.app /path/to/Quill.dmg" >&2
  exit 1
fi

APP_PATH=$1
OUTPUT_DMG=$2

if [ ! -d "$APP_PATH" ] || [ ! -f "$APP_PATH/Contents/Info.plist" ]; then
  echo "Error: $APP_PATH is not a macOS application bundle" >&2
  exit 1
fi

case "$OUTPUT_DMG" in
  *.dmg) ;;
  *)
    echo "Error: output path must end in .dmg" >&2
    exit 1
    ;;
esac

STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/quill-dmg.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT HUP INT TERM

mkdir -p "$(dirname "$OUTPUT_DMG")"
ditto "$APP_PATH" "$STAGING_DIR/Quill.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Quill" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$OUTPUT_DMG"

echo "Created $OUTPUT_DMG"

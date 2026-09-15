#!/bin/sh
set -eu

ACTION=${1:?Usage: publish-release.sh prepare|publish TAG IS_PRERELEASE}
TAG=${2:?Missing release tag}
IS_PRERELEASE=${3:?Missing prerelease flag}
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT_DIR/scripts/release-metadata.sh" "$TAG" "$IS_PRERELEASE" >/dev/null
: "${GITHUB_REPOSITORY:?Missing GITHUB_REPOSITORY}"

WORK_DIR=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/quill-release.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM

release_state() {
  release_tag=$1
  prerelease=$2
  state=$(gh api graphql \
    -f query='query($owner: String!, $name: String!, $tag: String!) { repository(owner: $owner, name: $name) { release(tagName: $tag) { isDraft isPrerelease } } }' \
    -f owner="${GITHUB_REPOSITORY%/*}" -f name="${GITHUB_REPOSITORY#*/}" -f tag="$release_tag" \
    --jq '.data.repository.release | if . == null then "missing" else "\(.isDraft) \(.isPrerelease)" end') || return 1
  case "$state" in
    missing) printf 'missing\n' ;;
    "true $prerelease") printf 'draft\n' ;;
    "false $prerelease") printf 'published\n' ;;
    *) echo "Error: $release_tag has the wrong prerelease setting" >&2; return 1 ;;
  esac
}

STATE=$(release_state "$TAG" "$IS_PRERELEASE")
if [ "$STATE" != published ]; then
  LATEST_TAG=$(gh api graphql \
    -f query='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { latestRelease { tagName } } }' \
    -f owner="${GITHUB_REPOSITORY%/*}" -f name="${GITHUB_REPOSITORY#*/}" \
    --jq '.data.repository.latestRelease.tagName // empty')
  python3 - "$TAG" "$LATEST_TAG" <<'PY'
import re
import sys

def version(tag):
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)(?:-rc\.\d+)?", tag)
    if not match:
        raise ValueError(f"Cannot compare release tag {tag!r}")
    return tuple(map(int, match.groups()))

if sys.argv[2] and version(sys.argv[1]) <= version(sys.argv[2]):
    sys.exit(f"Refusing unpublished {sys.argv[1]}: it must be newer than stable {sys.argv[2]}.")
PY
fi
case "$ACTION" in
  prepare)
    if [ "$STATE" = published ]; then
      printf 'needs_build=false\n'
    else
      printf 'needs_build=true\n'
    fi
    exit 0
    ;;
  publish) ;;
  *) echo "Unknown action: $ACTION" >&2; exit 1 ;;
esac

# A retry after publication must keep the original signed binaries and feed.
if [ "$STATE" != published ]; then
  : "${DMG_PATH:?Missing DMG_PATH}"
  : "${APPCAST_PATH:?Missing APPCAST_PATH}"
  if [ "$STATE" = missing ]; then
    gh release create "$TAG" --verify-tag --draft --prerelease="$IS_PRERELEASE" \
      --title "$TAG" --generate-notes
  fi
  cp "$DMG_PATH" "$WORK_DIR/Quill-macOS.dmg"
  gh release upload "$TAG" "$DMG_PATH" "$WORK_DIR/Quill-macOS.dmg" "$APPCAST_PATH" --clobber
  IS_LATEST=false
  if [ "$IS_PRERELEASE" = false ]; then IS_LATEST=true; fi
  gh release edit "$TAG" --draft=false --latest="$IS_LATEST"
fi

# Recover a failed channel publish using the feed attached to the public release.
gh release download "$TAG" --pattern appcast.xml --dir "$WORK_DIR"
RC_CHANNEL_TAG=quill-rc-channel
CHANNEL_STATE=$(release_state "$RC_CHANNEL_TAG" true)
mkdir "$WORK_DIR/current"
if [ "$CHANNEL_STATE" = published ]; then
  if ! gh release download "$RC_CHANNEL_TAG" --pattern appcast.xml --dir "$WORK_DIR/current"; then
    echo "Cannot verify RC channel history. Restore its last known appcast before retrying if the asset is missing." >&2
    exit 1
  fi
fi

SHOULD_PUBLISH=$(python3 - "$WORK_DIR/appcast.xml" "$WORK_DIR/current/appcast.xml" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

def latest_build(path):
    root = ET.parse(path).getroot()
    versions = [item.findtext("{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
                or item.find("enclosure").get("{http://www.andymatuschak.org/xml-namespaces/sparkle}version")
                for item in root.findall("./channel/item")]
    if not versions or any(not value or not value.isascii() or not value.isdigit() for value in versions):
        raise ValueError("Appcast must contain numeric Quill build versions")
    return max(map(int, versions))

candidate = latest_build(sys.argv[1])
current = pathlib.Path(sys.argv[2])
print("true" if not current.exists() or candidate > latest_build(current) else "false")
PY
)
if [ "$SHOULD_PUBLISH" != true ]; then
  echo "RC channel already contains this build or a newer build."
  exit 0
fi

if [ "$CHANNEL_STATE" = missing ]; then
  gh release create "$RC_CHANNEL_TAG" --target "$TAG" --draft --prerelease \
    --title "Quill release-candidate update channel" \
    --notes "Machine-managed Sparkle feed for opted-in release-candidate testers."
fi
gh release upload "$RC_CHANNEL_TAG" "$WORK_DIR/appcast.xml" --clobber
if [ "$CHANNEL_STATE" != published ]; then
  gh release edit "$RC_CHANNEL_TAG" --draft=false --latest=false
fi

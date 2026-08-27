#!/bin/sh
set -eu

TAG=${1:?Usage: release-metadata.sh TAG IS_PRERELEASE}
IS_PRERELEASE=${2:?Usage: release-metadata.sh TAG IS_PRERELEASE}
VERSION=${TAG#v}

case "$IS_PRERELEASE" in
  true)
    if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-rc\.[1-9][0-9]*$'; then
      echo "Prerelease tags must use vX.Y.Z-rc.N (N starts at 1)" >&2
      exit 1
    fi

    MARKETING_VERSION=${VERSION%%-rc.*}
    RC_NUMBER=${VERSION##*.}
    printf 'release_channel=rc\n'
    printf 'marketing_version=%s\n' "$MARKETING_VERSION"
    printf 'release_label=RC %s\n' "$RC_NUMBER"
    ;;
  false)
    if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "Stable release tags must use vX.Y.Z" >&2
      exit 1
    fi

    printf 'release_channel=stable\n'
    printf 'marketing_version=%s\n' "$VERSION"
    printf 'release_label=\n'
    ;;
  *)
    echo "IS_PRERELEASE must be true or false" >&2
    exit 1
    ;;
esac

#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT="$ROOT_DIR/scripts/release-metadata.sh"

assert_output() {
  expected=$1
  shift
  actual=$($SCRIPT "$@")
  if [ "$actual" != "$expected" ]; then
    echo "Unexpected metadata for $*" >&2
    echo "Expected:\n$expected" >&2
    echo "Actual:\n$actual" >&2
    exit 1
  fi
}

assert_rejected() {
  if "$SCRIPT" "$@" >/dev/null 2>&1; then
    echo "Expected metadata to be rejected for $*" >&2
    exit 1
  fi
}

assert_output 'release_channel=stable
marketing_version=1.2.3
release_label=' v1.2.3 false

assert_output 'release_channel=rc
marketing_version=2.0.0
release_label=RC 4' v2.0.0-rc.4 true

assert_rejected v1.2.3-rc.1 false
assert_rejected v1.2.3 true
assert_rejected v1.2.3-rc.0 true
assert_rejected v1.2.3-beta.1 true
assert_rejected release-1.2.3 false

echo "Release metadata tests passed"

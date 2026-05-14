#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${DEVELOPER_DIR:-}" == "" ]]; then
  if [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  elif [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
  fi
fi

if [[ "${DEVELOPER_DIR:-}" == "" ]]; then
  cat >&2 <<'EOF'
swift-test environment is not configured.

This project needs full Xcode on macOS for XCTest.
Install Xcode, then set:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

You can also run in CLion via the shared run configuration:
  Swift Test (core-swift)
EOF
  exit 2
fi

if [[ ! -x "${DEVELOPER_DIR}/usr/bin/xcodebuild" ]]; then
  echo "Invalid DEVELOPER_DIR: ${DEVELOPER_DIR}" >&2
  exit 2
fi

export PATH="${DEVELOPER_DIR}/usr/bin:${PATH}"
export SDKROOT="${SDKROOT:-macosx}"

cd "${ROOT_DIR}"
exec swift test "$@"

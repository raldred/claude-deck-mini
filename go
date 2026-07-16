#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"; shift || true
case "$cmd" in
  install) swift package resolve ;;
  build)   swift build "$@" ;;
  test)    swift test "$@" ;;
  run)     swift run "$@" ;;
  *) echo "usage: ./go {install|build|test|run}"; exit 1 ;;
esac

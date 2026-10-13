#!/usr/bin/env bash
# Esegue i test unitari, come la CI upstream (ninja -C build test)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${IN_NIX_SHELL:-}" ]; then
  exec nix-shell "$ROOT/shell.nix" --run "$(printf '%q ' "$0" "$@")"
fi

ninja -C "$ROOT/src/build" test

#!/usr/bin/env bash
# Build + install di Wayfire (con i sottoprogetti) in ./install
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Ogni comando di Claude Code parte in una shell nuova: lo script entra
# da solo nel nix-shell se non ci si trova già.
if [ -z "${IN_NIX_SHELL:-}" ]; then
  exec nix-shell "$ROOT/shell.nix" --run "$(printf '%q ' "$0" "$@")"
fi

cd "$ROOT/src"
if [ ! -d build ]; then
  meson setup build \
    --prefix="$ROOT/install" --libdir=lib \
    --buildtype=debugoptimized \
    -Duse_system_wlroots=disabled \
    -Duse_system_wfconfig=disabled
fi
ninja -C build
ninja -C build install

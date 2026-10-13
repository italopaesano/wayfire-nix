#!/usr/bin/env bash
# Protegge le dipendenze del nix-shell dal garbage collector:
# senza questa radice, un nix-collect-garbage può rompere la build installata.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.gcroots"
nix-build "$ROOT/shell.nix" -A inputDerivation -o "$ROOT/.gcroots/shell-inputs"

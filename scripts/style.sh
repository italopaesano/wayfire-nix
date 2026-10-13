#!/usr/bin/env bash
# Replica il controllo di stile della CI upstream: fork di uncrustify 0.71
# di ammen99 (maintainer di Wayfire), applicato a tutti i .cpp/.hpp tracciati.
# ATTENZIONE: modifica i file in src/. Eseguilo con nel working tree solo le tue
# modifiche: alla fine `git diff` deve mostrare esclusivamente quelle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${IN_NIX_SHELL:-}" ]; then
  exec nix-shell "$ROOT/shell.nix" --run "$(printf '%q ' "$0" "$@")"
fi

UNC_DIR="$ROOT/tools/uncrustify"
UNC="$UNC_DIR/build/uncrustify"
if [ ! -x "$UNC" ]; then
  git clone --depth 1 https://github.com/ammen99/uncrustify "$UNC_DIR"
  cmake -S "$UNC_DIR" -B "$UNC_DIR/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  cmake --build "$UNC_DIR/build" -j"$(nproc)"
fi

cd "$ROOT/src"
git ls-files | grep 'hpp$\|cpp$' | xargs "$UNC" -c uncrustify.ini --no-backup --replace -q
git --no-pager diff --stat

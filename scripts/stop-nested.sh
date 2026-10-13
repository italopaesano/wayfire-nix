#!/usr/bin/env bash
# Ferma SOLO la Wayfire nested di sviluppo, tramite il PID registrato.
# Non usare mai pkill/killall per nome: se il desktop è Wayfire,
# chiuderebbe anche la sessione grafica principale.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDF="$ROOT/logs/nested.pid"

[ -f "$PIDF" ] || { echo "Nessuna istanza nested registrata."; exit 0; }
PID="$(cat "$PIDF")"
EXE="$(readlink -f "/proc/$PID/exe" 2>/dev/null || true)"
WANT="$(readlink -f "$ROOT/install/bin/wayfire")"

if [ "$EXE" != "$WANT" ]; then
  echo "Il PID $PID non è la Wayfire di sviluppo (exe: ${EXE:-nessuno}): non lo termino." >&2
  rm -f "$PIDF"
  exit 1
fi
kill "$PID"
echo "Terminata Wayfire nested (PID $PID)."

#!/usr/bin/env bash
# Avvia la build di sviluppo di Wayfire NESTED (in una finestra del desktop corrente).
# Uso: scripts/run-nested.sh [argomenti extra per wayfire]
# Per fermarla: scripts/stop-nested.sh (mai pkill/killall per nome).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Sicurezza: senza un display padre wlroots sceglierebbe il backend DRM
# e da TTY prenderebbe il controllo dello schermo. Qui lo impediamo.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
  echo "Errore: nessun WAYLAND_DISPLAY/DISPLAY. Avvia da una sessione grafica." >&2
  exit 1
fi

if [ -z "${IN_NIX_SHELL:-}" ]; then
  exec nix-shell "$ROOT/shell.nix" --run "$(printf '%q ' "$0" "$@")"
fi

WF_BIN="$ROOT/install/bin/wayfire"
CONFIG="${WF_TEST_CONFIG:-$ROOT/config/wayfire-test.ini}"
PIDF="$ROOT/logs/nested.pid"
mkdir -p "$ROOT/logs"
LOG="$ROOT/logs/nested-$(date +%Y%m%d-%H%M%S).log"

[ -x "$WF_BIN" ] || { echo "Errore: $WF_BIN non trovato, esegui prima scripts/build.sh" >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "Errore: config $CONFIG non trovato" >&2; exit 1; }

export LD_LIBRARY_PATH="$ROOT/install/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
echo "Log: $LOG"

# -d prima di -c: -d accetta un argomento opzionale e altrimenti
# "mangerebbe" il primo argomento extra non preceduto da trattino.
"$WF_BIN" -d -c "$CONFIG" "$@" > >(tee "$LOG") 2>&1 &
WF_PID=$!
echo "$WF_PID" > "$PIDF"
trap 'rm -f "$PIDF"' EXIT
echo "PID Wayfire nested: $WF_PID"
wait "$WF_PID"

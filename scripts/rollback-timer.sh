#!/usr/bin/env bash
# Rete di sicurezza per i test rischiosi richiesti da CLAUDE.md: dopo N
# secondi ferma l'istanza indicata, se è ancora viva.
#
# Uso: scripts/rollback-timer.sh <secondi> <nested|vm> <pid> &
#
# Il PID è obbligatorio e non è un dettaglio: un timer che si limitasse a
# controllare "esiste un pidfile?" potrebbe fermare un'istanza diversa,
# avviata nel frattempo. È successo davvero il 2026-10-12, quando un timer
# residuo del primo avvio ha spento la seconda VM. Passando il PID atteso,
# lo stop avviene solo sull'istanza per cui il timer era stato armato.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ $# -eq 3 ] || { echo "Uso: $0 <secondi> <nested|vm> <pid>" >&2; exit 2; }
SECONDI="$1"; TIPO="$2"; PID="$3"
REG="$ROOT/logs/rollback-timer.log"
mkdir -p "$ROOT/logs"

case "$TIPO" in
  nested) STOP="$ROOT/scripts/stop-nested.sh" ;;
  vm)     STOP="$ROOT/scripts/stop-vm.sh" ;;
  *) echo "Tipo sconosciuto: $TIPO (usa 'nested' o 'vm')" >&2; exit 2 ;;
esac

sleep "$SECONDI"

if ! kill -0 "$PID" 2>/dev/null; then
  echo "$(date): timer $TIPO/$PID scaduto, processo già terminato." >> "$REG"
  exit 0
fi

echo "$(date): timer $TIPO scaduto, fermo il PID $PID." >> "$REG"
# stop-vm.sh accetta il PID atteso e rifiuta di agire su un'altra istanza.
if [ "$TIPO" = "vm" ]; then
  "$STOP" "$PID" >> "$REG" 2>&1
else
  "$STOP" >> "$REG" 2>&1
fi

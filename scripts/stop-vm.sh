#!/usr/bin/env bash
# Ferma SOLO la VM di test, tramite il PID registrato.
# Non usare mai pkill/killall per nome: sull'host girano altri processi
# (incluso, potenzialmente, il desktop Wayfire di Italo).
#
# Uso: scripts/stop-vm.sh [PID atteso]
# Se si passa un PID, lo script agisce solo se il pidfile contiene esattamente
# quello: serve ai timer di rollback, che devono fermare l'istanza per cui
# sono stati armati e non una VM diversa avviata nel frattempo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDF="$ROOT/logs/vm.pid"
ATTESO="${1:-}"

[ -f "$PIDF" ] || { echo "Nessuna VM registrata."; exit 0; }
PID="$(cat "$PIDF")"

if [ -n "$ATTESO" ] && [ "$PID" != "$ATTESO" ]; then
  echo "Il pidfile contiene $PID, non il $ATTESO che dovevo fermare:" \
       "è un'altra VM, non la tocco." >&2
  exit 0
fi

EXE="$(readlink -f "/proc/$PID/exe" 2>/dev/null || true)"

# Stessa logica di stop-nested.sh, ma l'eseguibile non è un path fisso:
# è il qemu dello store Nix usato dall'avviatore della VM. Verifichiamo
# quindi che sia davvero un qemu dello store, non un processo qualsiasi
# che ha ereditato il PID nel frattempo.
case "$EXE" in
  /nix/store/*qemu*|/nix/store/*/bin/qemu-system-*) ;;
  *)
    echo "Il PID $PID non è la VM di test (exe: ${EXE:-nessuno}): non lo termino." >&2
    rm -f "$PIDF"
    exit 1
    ;;
esac

# Spegnimento pulito: terminare il processo QEMU equivale a staccare la
# corrente al computer virtuale, e lascia il filesystem del guest sporco.
# Se SSH risponde si chiede al sistema ospite di spegnersi per davvero.
CHIAVE="$ROOT/vm/ssh/id_ed25519"
if [ -f "$CHIAVE" ] && timeout 10 ssh -i "$CHIAVE" -p 2222 \
     -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -o ConnectTimeout=5 wayfire@127.0.0.1 'sudo poweroff' >/dev/null 2>&1; then
  echo "Spegnimento ordinato richiesto alla VM (PID $PID), attendo..."
  for _ in $(seq 1 30); do
    kill -0 "$PID" 2>/dev/null || { echo "VM spenta correttamente."; exit 0; }
    sleep 1
  done
  echo "Non si è spenta entro 30 secondi: la termino." >&2
fi

kill "$PID"
echo "Terminata la VM (PID $PID)."

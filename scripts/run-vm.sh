#!/usr/bin/env bash
# Costruisce e avvia la VM di test NixOS con Wayfire sul backend DRM reale.
# Uso: scripts/run-vm.sh [argomenti extra per QEMU]
# Per fermarla: scripts/stop-vm.sh (mai pkill/killall per nome).
#
# A differenza di run-nested.sh questa NON tocca la sessione grafica
# dell'host: la VM è un normale processo utente in una finestra.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${IN_NIX_SHELL:-}" ]; then
  exec nix-shell "$ROOT/shell.nix" --run "$(printf '%q ' "$0" "$@")"
fi

PIDF="$ROOT/logs/vm.pid"
mkdir -p "$ROOT/logs" "$ROOT/.gcroots"
LOG="$ROOT/logs/vm-run-$(date +%Y%m%d-%H%M%S).log"

# KVM: senza, QEMU è configurato per fallire invece di emulare in software
# (forceAccel in vm/configuration.nix). Meglio dirlo subito e chiaramente.
[ -r /dev/kvm ] && [ -w /dev/kvm ] || {
  echo "Errore: /dev/kvm non accessibile in lettura/scrittura." >&2
  echo "Senza KVM la VM non parte (forceAccel). Verifica i permessi." >&2
  exit 1
}

# Versione reale dei sorgenti: .git è escluso dalla copia nello store
# (vedi vm/wayfire-dev.nix), quindi il commit va passato esplicitamente,
# altrimenti nel log della VM comparirebbe "unknown".
REV="$(git -C "$ROOT/src" rev-parse --short HEAD 2>/dev/null || echo unknown)"
BRANCH="$(git -C "$ROOT/src" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
echo "Sorgenti: $BRANCH @ $REV"

# Chiave SSH dedicata alla VM, generata al primo avvio. Non si usano le
# chiavi personali di Italo: questa serve solo per la VM di test.
SSHDIR="$ROOT/vm/ssh"
if [ ! -f "$SSHDIR/id_ed25519" ]; then
  echo "Genero una chiave SSH dedicata alla VM in vm/ssh/ ..."
  mkdir -p "$SSHDIR"
  ssh-keygen -t ed25519 -N "" -C "wayfire-vm" -f "$SSHDIR/id_ed25519" >/dev/null
fi

# Modalità grafica: software (sicura, predefinita), virgl o venus.
# Uso: WF_VM_GRAFICA=venus scripts/run-vm.sh
# ATTENZIONE: virgl e venus danno al guest accesso alla GPU reale e possono
# bloccarla (virgl l'ha gia' fatto il 2026-10-12). Vedi TODO.md.
GRAFICA="${WF_VM_GRAFICA:-software}"
case "$GRAFICA" in
  software) ;;
  virgl|venus)
    echo "ATTENZIONE: modalità '$GRAFICA' — il guest accede alla GPU reale." >&2
    echo "Un blocco della GPU dell'host è possibile: salva il lavoro aperto." >&2
    ;;
  *) echo "Modalità grafica sconosciuta: $GRAFICA (usa software|virgl|venus)" >&2; exit 2 ;;
esac
echo "Modalità grafica: $GRAFICA"

echo "Costruzione della VM (la prima volta è lunga: compila Wayfire e wlroots)..."
# L'output va in .gcroots/ come fa gcroot.sh: così un nix-collect-garbage
# non cancella la VM appena costruita.
nix-build "$ROOT/vm/default.nix" \
  --argstr rev "$REV" \
  --argstr branch "$BRANCH" \
  --argstr grafica "$GRAFICA" \
  -o "$ROOT/.gcroots/vm"

RUNNER="$(find "$ROOT/.gcroots/vm/bin" -maxdepth 1 -name 'run-*-vm' | head -1)"
[ -x "$RUNNER" ] || { echo "Errore: avviatore della VM non trovato in .gcroots/vm/bin" >&2; exit 1; }

# L'immagine disco sta in vm/, non nella directory corrente.
export NIX_DISK_IMAGE="$ROOT/vm/wayfire-vm.qcow2"

# venus: il render server di virglrenderer cerca libvulkan.so ma nixpkgs non
# gliela mette nel percorso di ricerca, e fallisce con
# "vkr: failed to open libvulkan". Gliela forniamo qui; QEMU lo lancia come
# processo figlio, che eredita l'ambiente. Verificato sul campo 2026-10-12.
if [ "$GRAFICA" = "venus" ]; then
  VULKAN_LIB="$(nix-build '<nixpkgs>' -A vulkan-loader --no-out-link 2>/dev/null)/lib"
  if [ -d "$VULKAN_LIB" ]; then
    export LD_LIBRARY_PATH="$VULKAN_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    echo "libvulkan fornita al render server: $VULKAN_LIB"
  else
    echo "ATTENZIONE: vulkan-loader non trovata, venus fallira'." >&2
  fi
fi

echo "Log: $LOG"
echo "SSH:  ssh -i vm/ssh/id_ed25519 -p 2222 wayfire@127.0.0.1"
echo "Il log della sessione Wayfire comparirà in logs/vm-*.log (cartella condivisa)."

"$RUNNER" "$@" > >(tee "$LOG") 2>&1 &
VM_PID=$!
echo "$VM_PID" > "$PIDF"
trap 'rm -f "$PIDF"' EXIT
echo "PID della VM: $VM_PID"
wait "$VM_PID"

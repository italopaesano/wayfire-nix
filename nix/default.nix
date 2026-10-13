# Punto di ingresso della VM di test.
#
#   nix-build vm/default.nix -o .gcroots/vm
#   ./.gcroots/vm/bin/run-wayfire-vm-vm
#
# ATTENZIONE, il motivo per cui questo file esiste: il NIX_PATH dell'host
# contiene `nixos-config=/etc/nixos/configuration.nix`. Un
# `nix-build '<nixpkgs/nixos>' -A vm` senza override valuterebbe quindi la
# configurazione reale della macchina di Italo (LUKS, hardware, servizi) —
# non ciò che vogliamo, e in contrasto con la regola di non toccare
# /etc/nixos. Chiamando eval-config.nix con moduli espliciti si costruisce
# solo ciò che è scritto qui dentro. Nessun sudo, nessun file di sistema.
{ pkgs ? import <nixpkgs> { }
, rev ? "unknown"
, branch ? "unknown"

  # Modalità grafica. Sono le tre strade che virglrenderer mette a
  # disposizione per dare accesso alla GPU al sistema ospite; vanno
  # confrontate (vedi TODO.md, "Accelerazione grafica nella VM").
  #
  #   software  nessun accesso alla GPU reale: rendering con llvmpipe (CPU).
  #             E' l'impostazione SICURA e il default. Basta per testare
  #             DRM/KMS, modesetting, input e logica del compositore.
  #   virgl     traduce OpenGL. PROVATA e BOCCIATA il 2026-10-12: ha causato
  #             un page fault e il reset della GPU dell'host.
  #   venus     passa Vulkan senza tradurre OpenGL, quindi evita il
  #             meccanismo che ha fallito con virgl. Da provare.
  #
  # ATTENZIONE: virgl e venus danno al guest accesso alla GPU reale e
  # possono bloccarla. Usarle solo come prove deliberate.
, grafica ? "software"
}:

assert pkgs.lib.assertOneOf "grafica" grafica [ "software" "virgl" "venus" ];

let
  wayfireDev = import ./wayfire-dev.nix { inherit pkgs rev branch; };
  wfShell = import ./wf-shell.nix { inherit pkgs wayfireDev; };
  wcm = import ./wcm.nix { inherit pkgs wayfireDev wfShell; };

  sistema = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [ ./configuration.nix ];
    specialArgs = {
      # Path assoluto della radice del progetto sull'host: serve per le
      # cartelle condivise (logs/, config/) e per la chiave SSH.
      hostRoot = toString ./..;
      inherit wayfireDev wfShell wcm grafica;
    };
  };
in
sistema.config.system.build.vm

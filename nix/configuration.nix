# Configurazione della VM di test per Wayfire.
#
# Scopo: eseguire Wayfire sul backend DRM reale, che sull'host sarebbe
# pericoloso (prenderebbe il controllo dello schermo). Qui wlroots trova un
# vero dispositivo /dev/dri e percorre modesetting, gestione output e input
# via libinput, cioè tutto ciò che il test nested su X11 non può coprire.
#
# Valutata da vm/default.nix con eval-config.nix: non legge /etc/nixos e non
# richiede sudo.
{ config, pkgs, lib, hostRoot, wayfireDev, wfShell, wcm, grafica, ... }:

let
  # Le tre modalità grafiche, scelte con --argstr grafica (vedi vm/default.nix
  # e scripts/run-vm.sh). Qui si traducono in opzioni QEMU e, nel caso di
  # venus, nel renderer che wlroots deve usare.
  # `-vga none` compare in TUTTE le modalita' e non va mai tolto: senza,
  # virtio-gpu si *aggiunge* alla VGA predefinita di QEMU e il guest si
  # ritrova due schede video. wlroots le inizializza entrambe, passa in
  # modalita' multi-GPU e fallisce a importare i buffer in un ciclo infinito
  # che riempie il log di centinaia di MB al minuto (successo il 2026-10-12:
  # 702 MB in poco piu' di un minuto).
  modi = {
    software = {
      qemu = [ "-vga none" "-device virtio-gpu-pci,xres=1280,yres=800" "-display gtk,gl=off" ];
      env = ''
        # Nessun accesso alla GPU reale: wlroots ripiega su llvmpipe (CPU).
        export WLR_RENDERER_ALLOW_SOFTWARE=1
      '';
    };

    virgl = {
      qemu = [ "-vga none" "-device virtio-gpu-gl-pci,xres=1280,yres=800" "-display gtk,gl=on" ];
      env = ''
        export WLR_RENDERER_ALLOW_SOFTWARE=1
      '';
    };

    venus = {
      # venus richiede le risorse "blob" e una finestra di memoria condivisa
      # con l'host: senza, il driver Vulkan del guest non parte.
      qemu = [
        "-vga none"
        "-device virtio-gpu-gl-pci,xres=1280,yres=800,venus=on,blob=true,hostmem=4G"
        "-display gtk,gl=on"
      ];
      env = ''
        # Con venus ha senso usare il renderer Vulkan di wlroots: e' il modo
        # diretto di sfruttarlo, senza passare da traduzioni OpenGL.
        # Nota: wlroots dichiara il proprio renderer Vulkan "sperimentale",
        # quindi qui si sommano due componenti sperimentali: se qualcosa non
        # va, puo' essere colpa dell'uno o dell'altro.
        export WLR_RENDERER=vulkan
        export WLR_RENDERER_ALLOW_SOFTWARE=1
      '';
    };
  };
  modo = modi.${grafica};
in
let
  # Riavvio del pannello dopo una modifica alla sua configurazione.
  #
  # Esiste perche' farlo a mano e' sorprendentemente facile da sbagliare: su
  # NixOS il processo NON si chiama "waybar" ma ".waybar-wrapped" (Nix avvolge
  # i binari in un wrapper), quindi `pkill waybar` non trova nulla e si
  # finisce per accumulare istanze sovrapposte. Qui si confronta l'intera
  # riga di comando e si aspetta la terminazione effettiva.
  riavviaPannello = pkgs.writeShellScriptBin "riavvia-pannello" ''
    set -u
    CFG="''${1:-/mnt/config/waybar-italo.json}"
    CSS="''${CFG%.json}.css"

    pkill -f 'waybar -c /mnt/config' 2>/dev/null || true
    for _ in $(seq 20); do
      pgrep -f 'waybar -c /mnt/config' >/dev/null || break
      sleep 0.5
    done
    # se qualcuna resiste al termine gentile, si insiste
    pkill -9 -f 'waybar -c /mnt/config' 2>/dev/null || true
    sleep 1

    ${pkgs.waybar}/bin/waybar -c "$CFG" -s "$CSS" >/tmp/waybar.log 2>&1 &
    sleep 3
    N=$(pgrep -cf 'waybar -c /mnt/config' || echo 0)
    echo "Pannello riavviato con $CFG (istanze attive: $N)"
    [ "$N" = "1" ] || echo "ATTENZIONE: attese 1 istanza, trovate $N" >&2
  '';

  # Avvio della sessione: scrive il log nella cartella condivisa, così è
  # leggibile dall'host senza entrare nella VM.
  #
  # Usa config/wayfire-vm.ini, non il wayfire-test.ini dei test nested: la
  # VM serve all'uso interattivo (decorazioni disegnate da Wayfire, sfondo,
  # pannello), mentre wayfire-test.ini resta volutamente spoglio e quasi
  # identico al wayfire.ini di upstream.
  sessioneWayfire = pkgs.writeShellScriptBin "sessione-wayfire" ''
    set -u
    LOGDIR=/mnt/logs
    mkdir -p "$LOGDIR" 2>/dev/null || LOGDIR=/tmp
    LOG="$LOGDIR/vm-$(date +%Y%m%d-%H%M%S).log"
    echo "Log della sessione VM: $LOG"

    # Quale configurazione usare: il nome sta in config/vm-config-attiva,
    # una riga sola, nella cartella condivisa. Cambiandolo si passa da una
    # configurazione all'altra riavviando la VM, senza ricostruire nulla.
    # Se il file manca o indica un file inesistente si ripiega sulla
    # configurazione di lavoro, così la VM parte comunque.
    CFG=/mnt/config/wayfire-vm.ini
    if [ -r /mnt/config/vm-config-attiva ]; then
      SCELTA=$(head -1 /mnt/config/vm-config-attiva | tr -d ' \t\r\n')
      if [ -n "$SCELTA" ] && [ -r "/mnt/config/$SCELTA" ]; then
        CFG="/mnt/config/$SCELTA"
      else
        echo "ATTENZIONE: '$SCELTA' non leggibile, uso wayfire-vm.ini"
      fi
    fi
    echo "Configurazione in uso: $CFG"

    # wf-shell cerca la propria configurazione in ~/.config/wf-shell.ini e
    # non legge wayfire.ini: si crea un collegamento alla copia nella
    # cartella condivisa, cosi' resta modificabile dall'host.
    mkdir -p "$HOME/.config"
    ln -sf /mnt/config/wf-shell-italo.ini "$HOME/.config/wf-shell.ini"

    echo "Modalita' grafica: ${grafica}"
${modo.env}

    # Cursore disegnato via software invece che con il "piano cursore" del
    # DRM. Serve per un difetto reale osservato in questa VM: con virtio-gpu
    # il cursore appare capovolto e, soprattutto, il punto in cui clicca non
    # coincide con la punta della freccia disegnata (scostamento misurato di
    # 6-9 pixel). Conseguenza pratica: i pulsanti della barra del titolo si
    # illuminavano quando la freccia era visibilmente altrove, e cliccarli
    # non funzionava. Non era un difetto di Wayfire: il piano cursore è
    # gestito da QEMU/virtio-gpu. Disegnandolo nella scena normale si
    # scavalca del tutto quel percorso.
    export WLR_NO_HARDWARE_CURSORS=1

    # Tetto da 256 MB al log. Questa VM serve anche a riprodurre bug, e un
    # compositore in errore può scrivere centinaia di MB al minuto (già
    # successo: 702 MB in poco più di un minuto). Raggiunto il tetto la
    # sessione termina invece di riempire il disco dell'host, visto che
    # /mnt/logs è una cartella condivisa.
    #
    # stdbuf -o0 NON è un dettaglio: senza, head bufferizza l'output e al
    # momento di un crash l'ultima parte del log — cioè proprio quella che
    # serve — resta nel buffer e va persa. Successo davvero il 2026-10-12:
    # la VM è crashata e il log si fermava all'avvio, 14 minuti prima.
    # -d per il log di debug, come in scripts/run-nested.sh
    exec ${wayfireDev}/bin/wayfire -d -c "$CFG" \
      2>&1 | stdbuf -o0 head -c 268435456 > "$LOG"
  '';
in
{
  imports = [
    # Le opzioni virtualisation.memorySize/cores/sharedDirectories ecc. NON
    # sono caricate di default: qemu-vm.nix non è in module-list.nix (vi
    # compare solo per generare la documentazione). Di norma lo aggiunge
    # build-vm.nix creando una "variante VM" di un sistema reale; qui la
    # configurazione è solo e sempre una VM, quindi lo importiamo diretto.
    # qemu-vm.nix definisce anche system.build.vm, che è ciò che
    # vm/default.nix restituisce.
    <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>

    # Profilo guest: initrd con 9p/virtio e virtio_gpu fra i kernelModules.
    <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
  ];

  # ── Macchina virtuale ──────────────────────────────────────────────────

  virtualisation = {
    memorySize = 4096;   # MiB; l'host ne ha 27 GB, 4 sono comodi e prudenti
    cores = 4;           # su 16 disponibili
    diskSize = 8192;     # MiB

    graphics = true;

    # NON usare virtualisation.resolution per impostare la risoluzione: agisce
    # sul percorso della VGA standard e con virtio-gpu viene semplicemente
    # ignorata. Verificato sul campo: impostata a 1280x800, il guest partiva
    # comunque a 640x480 (`wlr-randr` lo confermava). La risoluzione va
    # passata al dispositivo, vedi xres/yres in qemu.options più sotto.

    # Il qemu predefinito (qemu_kvm, "host-cpu-only") NON ha virglrenderer
    # linkato: il guest resterebbe senza accelerazione GL. Quello completo ce
    # l'ha, e permette di appoggiare il rendering alla GPU dell'host.
    qemu.package = pkgs.qemu;

    # Grafica: la parte più delicata di tutta la configurazione.
    #
    # 1. QEMU su x86 aggiunge virtio-gpu SOLO su aarch64: senza dichiararla
    #    si otterrebbe la VGA standard, che non espone /dev/dri — niente
    #    /dev/dri significa niente backend DRM, cioè la VM mancherebbe il
    #    suo unico scopo.
    # 2. `-vga none` è altrettanto necessario: senza, virtio-gpu si
    #    *aggiunge* alla VGA predefinita e il guest si ritrova due schede
    #    (bochs-drm + virtio_gpu). wlroots le inizializza entrambe, passa in
    #    modalità multi-GPU e fallisce a importare i buffer fra le due in un
    #    ciclo infinito ("Failed to import source buffer into multi-GPU
    #    renderer"), che riempie il log di centinaia di MB al minuto.
    #    Verificato sul campo: è successo davvero al primo avvio.
    # 3. virtio-gpu-gl + gl=on attivano virgl, cioè il passaggio dei comandi
    #    GL alla GPU dell'host.
    # 4. xres/yres impostano la risoluzione del guest: è QUI che va messa,
    #    non in virtualisation.resolution (ignorata da virtio-gpu).
    #
    # Difetti noti e accettati di questo percorso, entrambi lato QEMU e non
    # di Wayfire (verificato: durante i ridimensionamenti il compositore non
    # registra alcun evento, quindi non è coinvolto):
    #  - ridimensionando la finestra l'immagine diventa nera finché qualcosa
    #    non provoca un ridisegno (basta muovere il mouse o cliccare). QEMU
    #    perde il fotogramma e ne aspetta uno nuovo, ma un compositore
    #    Wayland disegna solo quando qualcosa cambia, e dentro la VM non è
    #    cambiato nulla;
    #  - il puntatore del mouse appare capovolto (texture del cursore
    #    ribaltata nel percorso GL di virtio-gpu).
    # Si è scelto di tenerli perché l'alternativa (gl=off) toglierebbe
    # l'accelerazione, e un compositore è un'applicazione GL: testarlo in
    # rendering software falserebbe le prove.
    # ATTENZIONE, accelerazione GL disattivata di proposito (2026-10-12).
    #
    # Con `-device virtio-gpu-gl-pci` e `gl=on` l'accelerazione funzionava,
    # ma ingrandendo una finestra a tutto schermo QEMU ha fatto accedere la
    # GPU dell'host a indirizzi non validi:
    #
    #   amdgpu: [gfxhub] page fault ... Process .qemu-system-x8
    #   amdgpu: ring gfx_0.0.0 timeout ... Starting gfx_0.0.0 ring reset
    #
    # Il kernel ha dovuto resettare l'anello grafico della scheda video
    # REALE. Quella volta il reset è riuscito e la sessione di Italo è
    # sopravvissuta, ma un blocco della GPU può anche congelare il desktop:
    # è esattamente il tipo di rischio che CLAUDE.md vieta di correre.
    #
    # Un guest non dovrebbe mai poter causare un page fault sulla GPU
    # dell'host: è un difetto di isolamento di virglrenderer, non di
    # Wayfire. Finché non è chiarito, si rinuncia all'accelerazione.
    #
    # Conseguenza: il rendering avviene via llvmpipe (CPU), grazie a
    # WLR_RENDERER_ALLOW_SOFTWARE impostata nello script di sessione. Più
    # lento, e i difetti specifici della GPU non si riprodurranno; restano
    # pienamente testabili DRM/KMS, modesetting, input e logica del
    # compositore, che sono lo scopo di questa VM.
    qemu.options = modo.qemu;

    # venus mappa le risorse "blob" fra guest e host, e per farlo la memoria
    # della VM deve essere condivisa (memory-backend-memfd con share=on).
    # Senza, il contesto venus non si crea: QEMU segnala
    # "virgl_render_server: failed to dispatch context op" e nel guest
    # vkCreateInstance fallisce con ERROR_OUT_OF_HOST_MEMORY — messaggio
    # fuorviante, non c'entra la memoria esaurita. Verificato sul campo.
    qemu.enableSharedMemory = (grafica == "venus");

    # Se KVM non fosse disponibile QEMU ripiegherebbe sull'emulazione
    # software, lentissima e con un comportamento grafico diverso: meglio
    # un errore esplicito. /dev/kvm sull'host ha permessi 0666, quindi va.
    qemu.forceAccel = true;

    # logs/ condivisa con l'host, come previsto da CLAUDE.md: i log della
    # sessione nella VM finiscono direttamente dove Italo li legge.
    # config/ in sola lettura: contiene wayfire-vm.ini usato dalla sessione.
    sharedDirectories = {
      wflogs = {
        source = "${hostRoot}/logs";
        target = "/mnt/logs";
      };
      wfconfig = {
        source = "${hostRoot}/config";
        target = "/mnt/config";
      };
    };

    # SSH raggiungibile solo da localhost: mai esposto sulla rete.
    forwardPorts = [
      { from = "host"; host = { address = "127.0.0.1"; port = 2222; }; guest.port = 22; }
    ];
  };

  # ── Grafica e sessione ─────────────────────────────────────────────────

  hardware.graphics.enable = true;   # in NixOS 26.05 sostituisce hardware.opengl

  # Simulazione dei tasti per il pulsante "mostra scrivania".
  #
  # Si usa ydotool e NON wtype, per un motivo preciso verificato sul campo:
  # wtype inventa un proprio layout di tastiera e invia i tasti attraverso
  # quello, mentre Wayfire associa le scorciatoie ai CODICI FISICI dei tasti
  # (KEY_D). Il codice scelto da wtype non corrisponde, e il 2026-10-12 ha
  # fatto comparire il menu di spegnimento invece di mostrare la scrivania:
  # era finito per caso sulla scorciatoia di wlogout.
  # ydotool invece scrive su /dev/uinput, quindi genera eventi identici a
  # quelli di una tastiera vera e i codici combaciano.
  programs.ydotool.enable = true;
  hardware.uinput.enable = true;

  # Vulkan nel guest: serve alla modalita' venus. Il driver e' l'ICD
  # "virtio" di mesa (virtio_icd.x86_64.json), che e' appunto venus.
  # Innocuo nelle altre modalita': se non c'e' un dispositivo Vulkan,
  # resta semplicemente inutilizzato.
  environment.variables.VK_ICD_FILENAMES =
    "/run/opengl-driver/share/vulkan/icd.d/virtio_icd.x86_64.json";

  # Risoluzione imposta al driver DRM. Né virtualisation.resolution né
  # xres/yres del dispositivo funzionano qui: verificato che l'EDID esposto
  # da virtio-gpu è vuoto (`/sys/class/drm/card0-Virtual-1/edid` = 0 byte),
  # quindi il connettore ripiega su una lista generica di modi in cui
  # 640x480 è il primo, e il guest partiva lì. Questo parametro scavalca
  # l'EDID e dice al driver quale modo usare.
  boot.kernelParams = [ "video=Virtual-1:1280x800" ];

  # Wayfire della build di sviluppo locale, non quello di nixpkgs (che è
  # 0.10.1 mentre noi testiamo master).
  environment.systemPackages = with pkgs; [
    wayfireDev
    foot                      # terminale impostato nella configurazione
    wlr-randr wayland-utils   # diagnosi output/protocolli
    libinput                  # libinput list-devices, per i test di input
    mesa-demos                # eglinfo/es2_info: verifica l'accelerazione
    vulkan-tools              # vulkaninfo: serve a verificare venus
    strace gdb

    # Sfondo e pannello. Parlano layer-shell, protocollo standard: funzionano
    # con qualunque compositore wlroots, quindi nessun vincolo alla versione
    # di Wayfire (wf-shell, il pannello ufficiale, non è in nixpkgs).
    # waybar porta con sé una configurazione predefinita in
    # /etc/xdg/waybar/config.jsonc, quindi parte senza che gliene scriviamo una.
    swaybg
    waybar

    # wf-shell e wcm compilati dai sorgenti GitHub contro il nostro 0.12:
    # quelli di nixpkgs sono fermi alla 0.10 e Wayfire li rifiuterebbe.
    wfShell                   # wf-panel, wf-dock, wf-background, wf-locker
    wcm                       # configurazione grafica di Wayfire
    riavviaPannello           # comando: riavvia-pannello

    # Senza queste, i pulsanti dei lanciatori e le icone delle finestre
    # resterebbero vuoti: waybar prende le icone dal tema di sistema e i
    # simboli dal font.
    papirus-icon-theme
    font-awesome

    # Programmi richiamati dalle scorciatoie della configurazione:
    # senza di loro la scorciatoia esiste ma non succede nulla.
    ydotool                   # simula i tasti: serve al pulsante "mostra scrivania"
    wofi                      # Super+Shift+Invio, lanciatore
    swaylock                  # Super+Shift+Esc, blocco schermo
    wlogout                   # Super+Esc, uscita dalla sessione
    grim slurp                # Stamp, schermate dall'interno della VM
    wl-clipboard

    # Qualche finestra con cui esercitare davvero il compositore: spostare,
    # ridimensionare, affiancare, passare fra workspace, provare expo e cube.
    # Con un solo terminale non si proverebbe granché.
    xterm
    mousepad                  # editor di testo GTK
    pcmanfm                   # gestore file
    galculator
  ];

  # Avvio della sessione: greetd gestisce il login (così si prova anche quel
  # percorso), ma initial_session entra diretto al desktop per non dover
  # digitare la password a ogni avvio.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "${sessioneWayfire}/bin/sessione-wayfire";
        user = "wayfire";
      };
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time "
          + "--cmd ${sessioneWayfire}/bin/sessione-wayfire";
        user = "greeter";
      };
    };
  };

  # ── Utente ─────────────────────────────────────────────────────────────

  users.users.wayfire = {
    isNormalUser = true;
    description = "Utente di test Wayfire";
    extraGroups = [ "wheel" "video" "input" "ydotool" ];
    # VM locale di test, non raggiungibile dall'esterno: password nota e
    # banale per comodità in console. L'accesso SSH è invece a chiave.
    password = "wayfire";
    openssh.authorizedKeys.keyFiles =
      lib.optional (builtins.pathExists "${hostRoot}/vm/ssh/id_ed25519.pub")
        "${hostRoot}/vm/ssh/id_ed25519.pub";
  };

  users.users.root.password = "root";
  security.sudo.wheelNeedsPassword = false;

  # ── Rete e accesso ─────────────────────────────────────────────────────

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;   # solo chiave
      PermitRootLogin = "no";
    };
  };

  networking.hostName = "wayfire-vm";
  networking.firewall.enable = false;   # VM isolata dietro NAT di QEMU

  # ── Varie ──────────────────────────────────────────────────────────────

  time.timeZone = "Europe/Rome";
  console.keyMap = "it";
  services.xserver.xkb.layout = "it";

  # Niente documentazione: accorcia la costruzione, è una VM usa e getta.
  documentation.enable = false;
  documentation.nixos.enable = false;

  system.stateVersion = "26.05";
}

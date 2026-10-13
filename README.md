# wayfire-nix

Infrastruttura Nix per compilare e provare [Wayfire](https://github.com/WayfireWM/wayfire)
dal ramo di sviluppo, con una macchina virtuale di prova e l'ecosistema di
pacchetti che gli gira attorno.

Non è codice Wayfire: è il modo in cui lo si costruisce e lo si mette alla
prova senza toccare il desktop su cui si lavora.

## Cosa risolve

Provare un compositore Wayland pone un problema pratico: eseguirlo sulla
macchina su cui stai lavorando significa che un difetto può prenderti il
controllo dello schermo. Qui ci sono due livelli di prova:

- **annidato** (`scripts/run-nested.sh`) — Wayfire dentro una finestra della
  sessione corrente, rapido ma limitato: usa il backend X11;
- **macchina virtuale** (`scripts/run-vm.sh`) — Wayfire su un vero percorso
  DRM/KMS, con modesetting e input diretto, cioè ciò che il test annidato non
  può coprire. Costruita con `nixos/lib/eval-config.nix`: non legge
  `/etc/nixos` e non richiede privilegi di amministratore.

## Uso rapido: compilare Wayfire con le patch

Richiede che siano abilitate le funzionalità sperimentali di Nix
(`experimental-features = nix-command flakes`).

```sh
nix build .#wayfire
./result/bin/wayfire --version
```

Il flake **scarica i sorgenti da GitHub**, fissati in `flake.lock` a un
commit preciso, e vi applica le patch in `patches/`. Non dipende da alcun
clone locale: funziona su qualunque macchina con Nix, e ricostruisce
esattamente la stessa cosa.

Per lavorare sui sorgenti a mano:

```sh
nix develop
```

## Le patch

| patch | cosa fa |
|---|---|
| `patches/cube-absolute-pointer.patch` | fa ruotare il cubo anche con dispositivi di puntamento **assoluti** — tavolette grafiche, touchscreen, e le tavolette virtuali che QEMU, VirtualBox e VMware presentano ai sistemi ospiti. Senza, il cubo si apre ma non ruota trascinando. |

Le patch sono applicate sopra i sorgenti upstream, non su un fork: resta
chiaro cosa è originale e cosa è aggiunto, e il materiale è pronto da
proporre a monte.

## Due modi d'uso, con requisiti diversi

Il contenuto si divide in due parti, ed è bene non confonderle.

**Il flake è autonomo.** Scarica tutto da solo, non richiede nient'altro e
funziona su qualunque macchina con Nix. È quanto serve per compilare e
provare Wayfire con le patch.

**Gli script e la macchina virtuale richiedono un clone locale** di Wayfire
in `src/`, perché servono il ciclo di sviluppo: compilano ciò che hai sotto
mano, non ciò che sta su GitHub. Il clone non è incluso qui — va creato:

```sh
git clone https://github.com/WayfireWM/wayfire.git src
git -C src submodule update --init --recursive
```

Senza quella cartella `scripts/build.sh`, `scripts/run-vm.sh` e gli altri non
hanno nulla da compilare.

## Le espressioni in `nix/`

| file | contenuto |
|---|---|
| `wayfire-dev.nix` | Wayfire da un clone locale (per il ciclo di sviluppo) |
| `wf-shell.nix` | pannello, sfondo, dock e blocco schermo ufficiali |
| `wcm.nix` | pannello di configurazione grafico |
| `wayfire-plugins-extra.nix` | 24 plugin aggiuntivi, fra cui fisheye e le ombre |
| `configuration.nix` | il sistema NixOS della macchina virtuale |
| `default.nix` | punto di ingresso della VM |

**Tutti compilati dai sorgenti GitHub, non dai pacchetti nixpkgs.** Non è
pignoleria: i plugin di Wayfire sono librerie caricate dentro il processo del
compositore, e Wayfire **rifiuta** quelle costruite per una versione diversa
della propria interfaccia binaria. I pacchetti `wayfirePlugins.*` di nixpkgs
sono fermi alla 0.10 mentre lo sviluppo è sulla 0.12 — e non è solo un numero:
wf-shell nel frattempo è passato da GTK3 a GTK4.

### Dipendenze non ovvie, trovate per tentativi

Annotate anche nei file, perché nessuna è documentata in modo evidente:

- **glm** serve a chiunque compili contro Wayfire: i suoi header pubblici lo
  includono, ma `wayfire.pc` non lo dichiara fra i requisiti;
- **wf-shell** richiede `pam`, usa un sottomodulo git (`gvc`) che va scaricato
  esplicitamente, e vuole `yyjson`, `pipewire`, `wireplumber`, `ddcutil`;
- **wcm** richiede wf-shell per compilare, quindi l'ordine è obbligato;
- **wayfire-plugins-extra** installa i propri metadati nella cartella di
  Wayfire, che in Nix è di sola lettura: i percorsi vanno scavalcati con le
  variabili `PKG_CONFIG_WAYFIRE_*`.

## La macchina virtuale

```sh
scripts/run-vm.sh          # avvia (modalità grafica sicura)
scripts/stop-vm.sh         # ferma
```

Espone SSH su `127.0.0.1:2222` con una chiave dedicata generata al primo
avvio, e condivide `logs/` e `config/` con l'host, così le configurazioni si
modificano da fuori senza ricostruire nulla.

### Accelerazione grafica: attenzione

`WF_VM_GRAFICA` sceglie fra tre modalità:

| modalità | cosa fa | stato |
|---|---|---|
| `software` (predefinita) | rendering su CPU, nessun accesso alla GPU reale | **sicura** |
| `virgl` | traduce OpenGL verso la GPU dell'host | **sconsigliata**: ha causato un page fault e il reset della GPU dell'host |
| `venus` | passa Vulkan invece di tradurre OpenGL | inizializza correttamente, ma il compositore non parte |

La modalità predefinita rinuncia all'accelerazione di proposito. DRM/KMS,
modesetting, input e logica del compositore restano pienamente verificabili;
si perdono fedeltà del rendering e prestazioni.

## Avvertenze

Gli script non usano mai `sudo` e non scrivono fuori dalla cartella del
progetto. Per fermare le istanze di prova usano il PID registrato, verificato
tramite `/proc/<pid>/exe`, mai il nome del processo: su una macchina il cui
desktop è Wayfire, terminare per nome chiuderebbe anche la sessione in uso.

`scripts/rollback-timer.sh` ferma automaticamente una prova lasciata aperta,
e richiede il PID da sorvegliare proprio per non colpire un'istanza diversa
avviata nel frattempo.

# wayfire-nix

Strumenti per compilare, correggere e provare
[Wayfire](https://github.com/WayfireWM/wayfire) — un compositore Wayland —
usando Nix.

Qui non c'è codice di Wayfire: c'è il modo di costruirlo, di applicargli
delle correzioni e di metterlo alla prova **senza rischiare la sessione
grafica su cui si sta lavorando**.

---

## Il problema che risolve

Chi vuole modificare un compositore si trova davanti due ostacoli pratici.

**Il primo è che non lo puoi provare dove lavori.** Un compositore è il
programma che disegna le finestre e gestisce tastiera e mouse. Se lo avvii
normalmente prende il controllo dello schermo; se la versione che stai
provando ha un difetto, resti senza interfaccia grafica e magari perdi il
lavoro aperto.

**Il secondo è che ricostruire l'ambiente è laborioso.** Wayfire si compila
assieme a wlroots e ad altri quattro sottoprogetti, ha un ecosistema di
pannelli e plugin che devono combaciare esattamente con la sua versione, e
diverse dipendenze non sono documentate: le scopri una per volta, a ogni
tentativo fallito.

Questo repository affronta entrambi: una ricetta riproducibile per
costruire, e due ambienti sicuri in cui provare.

---

## Cosa contiene

### Un flake per compilare Wayfire con le correzioni

Scarica i sorgenti da GitHub, vi applica le patch di `patches/` e produce un
Wayfire funzionante. Le versioni di tutto — sorgenti, compilatore, librerie —
sono fissate in `flake.lock`: la stessa ricetta dà lo stesso risultato su
qualunque macchina, oggi e fra un anno.

### Due ambienti di prova

**Annidato**: Wayfire dentro una finestra della sessione in corso. Parte in
pochi secondi, ma usa il backend X11, quindi non esercita il percorso reale
di gestione dello schermo.

**Macchina virtuale**: un sistema NixOS completo in cui Wayfire pilota uno
schermo vero attraverso DRM/KMS, con input diretto e sessione di login. È
l'unico modo di provare ciò che il test annidato non copre, e tutto resta
confinato in una finestra.

### Le ricette per l'ecosistema

`wf-shell` (pannello, sfondo, dock, blocco schermo), `wcm` (configurazione
grafica) e `wayfire-plugins-extra` (24 plugin aggiuntivi), compilati dai
sorgenti del progetto contro la versione di Wayfire che si sta usando.

---

## Perché non si usano i pacchetti già pronti di nixpkgs

Non è pignoleria. I plugin di Wayfire sono librerie caricate **dentro** il
processo del compositore, e Wayfire rifiuta di caricare quelle costruite per
una versione diversa della propria interfaccia binaria: le scarta con un
messaggio di errore, perché caricarle provocherebbe un crash.

I pacchetti `wayfirePlugins.*` di nixpkgs sono fermi alla 0.10, mentre lo
sviluppo è sulla 0.12. E non è solo una differenza di numero: nel frattempo
wf-shell è passato da GTK3 a GTK4, cioè a un'altra libreria grafica.

---

## Uso

Serve [Nix](https://nixos.org/download) con le funzionalità sperimentali
abilitate:

```
experimental-features = nix-command flakes
```

### Compilare Wayfire con le patch

```sh
nix build github:italopaesano/wayfire-nix#wayfire
./result/bin/wayfire --version
```

Non serve clonare nulla: Nix scarica il necessario e compila. La prima volta
richiede parecchi minuti, perché costruisce anche wlroots.

### Ambiente di sviluppo

```sh
nix develop github:italopaesano/wayfire-nix
```

Entra in una shell con compilatore, dipendenze e strumenti di diagnosi.

### Script e macchina virtuale

Richiedono il repository clonato **e** un clone di Wayfire in `src/`, perché
compilano i sorgenti che hai sotto mano anziché quelli remoti:

```sh
git clone https://github.com/italopaesano/wayfire-nix
cd wayfire-nix
git clone https://github.com/WayfireWM/wayfire.git src
git -C src submodule update --init --recursive

scripts/build.sh        # compila in install/
scripts/test.sh         # test unitari
scripts/run-nested.sh   # prova annidata
scripts/run-vm.sh       # macchina virtuale
```

La macchina virtuale espone SSH su `127.0.0.1:2222` con una chiave dedicata
generata al primo avvio, e condivide `logs/` e `config/` con l'host: le
configurazioni si modificano da fuori senza ricostruire nulla.

---

## Le patch

| patch | cosa corregge |
|---|---|
| `cube-absolute-pointer` | il cubo dei workspace non ruotava trascinando con **dispositivi di puntamento assoluti**: tavolette grafiche, touchscreen, e le tavolette virtuali che QEMU, VirtualBox e VMware presentano ai sistemi ospiti. Il plugin ascoltava soltanto il movimento *relativo*, che quei dispositivi non producono. |

Le patch sono applicate sopra i sorgenti originali anziché su un fork: resta
evidente cosa è di Wayfire e cosa è aggiunto, e il materiale è pronto da
proporre al progetto.

---

## Accelerazione grafica nella macchina virtuale: leggere prima di cambiare

`WF_VM_GRAFICA` sceglie come la VM accede alla grafica:

| modalità | cosa fa | esito |
|---|---|---|
| `software` (predefinita) | disegna con la CPU, nessun accesso alla GPU reale | **sicura** |
| `virgl` | traduce i comandi OpenGL verso la GPU dell'host | **ha resettato la GPU dell'host**: un page fault ha costretto il kernel a reinizializzare la scheda video |
| `venus` | passa Vulkan senza tradurre OpenGL | si avvia, ma il compositore non parte |

La modalità predefinita rinuncia all'accelerazione di proposito. Restano
pienamente verificabili DRM/KMS, modesetting, input e logica del
compositore; si perdono fedeltà del rendering e prestazioni.

Un guest non dovrebbe mai poter bloccare la GPU dell'host: è un difetto di
isolamento del livello di traduzione, non di Wayfire.

---

## Dipendenze non ovvie, trovate per tentativi

Annotate anche nei singoli file, perché nessuna è documentata in modo
evidente e ritrovarle costa tempo:

- **glm** serve a chiunque compili qualcosa contro Wayfire: i suoi header
  pubblici lo includono, ma `wayfire.pc` non lo dichiara fra i requisiti;
- **wf-shell** richiede `pam`, usa un sottomodulo git (`gvc`) che va chiesto
  esplicitamente, e vuole `yyjson`, `pipewire`, `wireplumber`, `ddcutil`;
- **wcm** richiede wf-shell per compilare: l'ordine è obbligato;
- **wayfire-plugins-extra** installa i propri metadati nella cartella di
  Wayfire, che in Nix è di sola lettura; i percorsi vanno scavalcati con le
  variabili d'ambiente `PKG_CONFIG_WAYFIRE_*`.

---

## Avvertenze

Gli script non usano mai `sudo` e non scrivono fuori dalla cartella del
progetto. La macchina virtuale è costruita con `nixos/lib/eval-config.nix`,
quindi non legge la configurazione di sistema dell'host.

Per fermare le istanze di prova usano il PID registrato, **verificato
tramite `/proc/<pid>/exe`**, mai il nome del processo: su una macchina il cui
desktop è Wayfire, terminare per nome chiuderebbe anche la sessione in uso.

`scripts/rollback-timer.sh` chiude automaticamente una prova lasciata aperta,
e pretende il PID da sorvegliare proprio per non colpire un'istanza diversa
avviata nel frattempo.

---

## Usarlo come desktop quotidiano

Questo repository costruisce un **binario**, non un ambiente desktop pronto.
Per usare Wayfire tutti i giorni servono alcune cose che qui non ci sono:

- una voce di sessione, perché il gestore di login sappia che esiste;
- la gestione del *seat*, cioè i permessi su tastiera, mouse e scheda video
  senza privilegi di amministratore;
- i portali XDG, per condivisione schermo, scelta file e apertura dei link;
- integrazione con PAM e polkit per blocco schermo e autenticazione.

### Su NixOS la strada è breve

Quasi tutto l'elenco **non va scritto**: NixOS ha già il modulo
`programs.wayfire`, che registra la sessione nel gestore di login e
configura i portali XDG. Basta dirgli di usare il pacchetto costruito qui
invece di quello predefinito di nixpkgs:

```nix
# flake.nix della configurazione di sistema
{
  inputs.wayfire-nix.url = "github:italopaesano/wayfire-nix";
  # ...
}
```

```nix
# nella configurazione della macchina
programs.wayfire = {
  enable = true;
  package = inputs.wayfire-nix.packages.${pkgs.system}.wayfire;
};
```

Al riavvio il compositore compare fra le sessioni disponibili al login.

### Tre cose da sapere prima di farlo

**La build è `debugoptimized`.** Mantiene i simboli per leggere i backtrace,
il che è prezioso quando qualcosa va storto, ma non è una build ottimizzata
per l'uso quotidiano.

**La versione è fissata a un commit preciso.** È la qualità che rende
riproducibili gli esperimenti, ma significa che il sistema non riceve
aggiornamenti di Wayfire finché non si aggiorna `flake.lock` a mano.

**È il ramo di sviluppo, non una versione rilasciata.** Può contenere
regressioni che nessuno ha ancora notato. Per un sistema su cui conti
davvero, conviene tenere installata anche una sessione alternativa — il
gestore di login permette di scegliere all'accesso, e averne una funzionante
sotto mano evita di restare a piedi.

---

## Stato

Materiale di lavoro, non un prodotto finito: è pensato per lo sviluppo e la
prova di Wayfire. Per l'uso quotidiano vedi la sezione qui sopra.

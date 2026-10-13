# Wayfire compilato dai sorgenti locali in src/, come pacchetto Nix.
# Usa le stesse opzioni meson di scripts/build.sh, così la VM prova
# esattamente ciò che si compila in locale: wlroots e wf-config dai
# submodule, non quelli di sistema.
#
# rev/branch: iniettati dall'esterno (scripts/run-vm.sh li legge con git).
# Servono perché .git è escluso dalla copia dei sorgenti, vedi sotto.
# sorgenti: percorso di un clone di Wayfire con i sottomoduli inizializzati.
# Il valore predefinito assume la disposizione dell'ambiente di lavoro
# (questo repository affiancato a un clone in ../src). Per compilare altrove
# si passa il percorso, oppure si usa il flake alla radice, che scarica i
# sorgenti da GitHub e non dipende da nessun clone locale.
{ pkgs ? import <nixpkgs> { }
, sorgenti ? ../../src
, rev ? "unknown"
, branch ? "unknown"
}:

let
  lib = pkgs.lib;

  # Serve solo per ereditare le dipendenze di build di wlroots 0.20,
  # stessa logica di shell.nix: la libreria usata è quella del submodule.
  wlrootsRef = pkgs.wlroots_0_20 or pkgs.wlroots;

  # Raccoglie una categoria di dipendenze da wayfire e wlroots di nixpkgs,
  # come fa inputsFrom di mkShell in shell.nix.
  fonti = [ pkgs.wayfire wlrootsRef ];
  deps = categoria: lib.concatMap (p: p.${categoria} or [ ]) fonti;

  sorgentiRaw = sorgenti;

  # src/ pesa 1,8 GB, ma 1,7 sono build/ e 42 MB .git. Senza filtro ogni
  # ricostruzione copierebbe tutto nello store. Filtrati restano ~14 MB.
  #
  # .git è escluso anche per un secondo motivo: il suo contenuto cambia a
  # ogni operazione git (anche un semplice fetch), e cambierebbe l'hash
  # della derivazione provocando ricompilazioni senza che il codice sia
  # cambiato.
  #
  # I submodule NON vanno esclusi: sono già completi su disco ed è
  # indispensabile, perché le derivazioni Nix compilano in isolamento,
  # senza accesso alla rete.
  sorgenti = lib.cleanSourceWith {
    name = "wayfire-src";
    src = sorgentiRaw;
    filter = path: type:
      let
        rel = lib.removePrefix (toString sorgentiRaw + "/") (toString path);
        base = baseNameOf (toString path);
      in
      # solo la build/ di primo livello, non directory omonime nei sottoprogetti
      !(type == "directory" && rel == "build")
      && base != ".git";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "wayfire-dev";
  version = "0.12.0-${rev}";

  src = sorgenti;

  # Riuso delle dipendenze dei pacchetti esistenti invece di elencarle a
  # mano: è lo stesso approccio di shell.nix (inputsFrom), già dimostrato
  # sufficiente per la build locale della sessione 1.
  #
  # Attenzione: NON bastano le buildInputs. `inputsFrom` di mkShell raccoglie
  # anche le dipendenze *propagate*, ed è lì che stanno pezzi indispensabili
  # come cairo: prendendo solo buildInputs la build fallisce con
  # «Dependency "cairo" not found». Qui si replica ciò che fa inputsFrom.
  nativeBuildInputs = deps "nativeBuildInputs" ++ deps "propagatedNativeBuildInputs"
    ++ (with pkgs; [ meson ninja pkg-config cmake wayland-scanner ]);

  # glm e udev non compaiono fra le dipendenze del wayfire 0.10.1 di
  # nixpkgs, ma il meson.build di master le richiede entrambe
  # (src/meson.build:45 per libudev; glm è `required: false` ma le righe
  # 131-132 interrompono la build se manca anche l'header glm/glm.hpp).
  buildInputs = deps "buildInputs" ++ deps "propagatedBuildInputs"
    ++ (with pkgs; [ glm udev ]);

  # vcs_tag in src/meson.build sostituisce @GIT_COMMIT@/@GIT_BRANCH@ con
  # l'output di git; senza .git ripiegherebbe su "unknown". Scrivendo i
  # valori direttamente nei file .in, vcs_tag non trova più il segnaposto e
  # li lascia intatti: la VM mostra così il commit vero nel log d'avvio.
  postPatch = ''
    substituteInPlace src/version/git-commit.cpp.in \
      --replace '@GIT_COMMIT@' '${rev}'
    substituteInPlace src/version/git-branch.cpp.in \
      --replace '@GIT_BRANCH@' '${branch}'
  '';

  mesonFlags = [
    "-Duse_system_wlroots=disabled"
    "-Duse_system_wfconfig=disabled"
    "-Dtests=disabled"
  ];

  # debugoptimized come scripts/build.sh: i backtrace restano leggibili,
  # utile visto che la VM serve anche a riprodurre bug.
  mesonBuildType = "debugoptimized";

  meta = with lib; {
    description = "Wayfire compilato dai sorgenti di sviluppo locali";
    mainProgram = "wayfire";
    platforms = platforms.linux;
  };
}

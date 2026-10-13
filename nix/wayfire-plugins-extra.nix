# wayfire-plugins-extra — plugin aggiuntivi ufficiali.
#
# Contiene fra l'altro il fisheye spostato qui dal repository principale
# (commit 40544c89, la nostra prima PR riguardava proprio i riferimenti
# rimasti), e dalla versione corrente anche wayfire-shadows (le ombre sotto
# le finestre), che nixpkgs segnalava come pacchetto separato ma e' stato
# assorbito qui.
#
# Compilato dai sorgenti GitHub contro il nostro Wayfire 0.12: i plugin sono
# librerie caricate dentro il compositore e Wayfire rifiuta quelle costruite
# per una ABI diversa (src/core/plugin-loader.cpp:110).
#
# Nota: degli altri due pacchetti che avevo citato, firedecor e windecor,
# nixpkgs li ha RIMOSSI perche' non piu' mantenuti.
{ pkgs ? import <nixpkgs> { }
, wayfireDev
, rev ? "ec89a23f37705ae3c3a6020289148c451d7817a3"   # master al 2026-10-13
}:

let
  lib = pkgs.lib;

  sorgenti = builtins.fetchGit {
    url = "https://github.com/WayfireWM/wayfire-plugins-extra.git";
    inherit rev;
    allRefs = true;
    submodules = true;
  };
in
pkgs.stdenv.mkDerivation {
  pname = "wayfire-plugins-extra-dev";
  version = "git-${builtins.substring 0 8 rev}";
  src = sorgenti;

  nativeBuildInputs = with pkgs; [
    meson ninja pkg-config cmake
    wayland-scanner
  ];

  buildInputs = [ wayfireDev ] ++ (with pkgs; [
    # glm: gli header di Wayfire lo includono ma wayfire.pc non lo dichiara
    # fra i Requires. Vedi TODO.md, possibile difetto da segnalare a monte.
    glm

    boost
    gtkmm3
    libdrm
    # i sorgenti includono <drm_fourcc.h> direttamente, ma l'header sta in
    # ${libdrm}/include/libdrm: senza questo percorso la compilazione
    # fallisce con «fatal error: drm_fourcc.h: No such file or directory»
    libevdev
    libinput
    libxkbcommon
    xcbutilwm
    vulkan-headers
    wayland
    wayland-protocols
    cairo
    pango
    pixman
    libxml2
    yyjson
    libgbm
  ]);

  # Aggiunge il percorso degli header di libdrm, non esposto di default.
  NIX_CFLAGS_COMPILE = "-I${pkgs.libdrm.dev}/include/libdrm";

  # I plugin installano i propri metadati e dati nelle cartelle che leggono
  # dal file wayfire.pc:
  #     install_dir: wayfire.get_variable(pkgconfig: 'metadatadir')
  # Quei percorsi puntano dentro il pacchetto di Wayfire, che in Nix e' di
  # sola lettura: l'installazione falliva con
  #     PermissionError: Permission denied: .../share/wayfire/metadata/annotate.xml
  # Su una distribuzione normale sarebbe /usr/share/wayfire/metadata e non
  # darebbe problemi; e' un attrito fra il modello di Nix e il modo in cui i
  # plugin di Wayfire si installano.
  #
  # pkg-config permette di sovrascrivere una variabile dall'ambiente con
  # PKG_CONFIG_<PACCHETTO>_<VARIABILE>: cosi' i file finiscono nel pacchetto
  # dei plugin invece che in quello di Wayfire. Wayfire li trovera' comunque,
  # perche' il percorso dei plugin e dei metadati e' configurabile a runtime.
  preConfigure = ''
    export PKG_CONFIG_WAYFIRE_METADATADIR="$out/share/wayfire/metadata"
    export PKG_CONFIG_WAYFIRE_PKGDATADIR="$out/share/wayfire/protocols"
    export PKG_CONFIG_WAYFIRE_PLUGINDIR="$out/lib/wayfire"
  '';

  meta = with lib; {
    description = "Plugin aggiuntivi di Wayfire, compilati contro la nostra build";
    platforms = platforms.linux;
  };
}

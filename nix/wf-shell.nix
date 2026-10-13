# wf-shell — pannello, sfondo e dock ufficiali di Wayfire.
#
# Compilato dai sorgenti di GitHub e NON dal pacchetto nixpkgs, fermo alla
# 0.10.0: Wayfire rifiuta i componenti costruiti per una ABI diversa dalla
# propria, e noi eseguiamo 0.12.0 master.
#
# Va compilato PRIMA di wcm, che lo richiede come dipendenza pkg-config
# (verificato: il meson di wcm si interrompe con «Dependency "wf-shell" not
# found»).
{ pkgs ? import <nixpkgs> { }
, wayfireDev                       # il nostro Wayfire 0.12.0
, rev ? "f317d07a4fbf11b6fc1d940a21b1f3b4b0fd0cdd"   # master al 2026-10-13
}:

let
  lib = pkgs.lib;

  sorgenti = builtins.fetchGit {
    url = "https://github.com/WayfireWM/wf-shell.git";
    inherit rev;
    allRefs = true;
    # wf-shell usa un sottomodulo (gvc, il controllo del volume) e fetchGit
    # non li scarica di default: senza questo, meson si ferma con
    # «Subproject exists but has no meson.build file».
    submodules = true;
  };
in
pkgs.stdenv.mkDerivation {
  pname = "wf-shell-dev";
  version = "git-${builtins.substring 0 8 rev}";
  src = sorgenti;

  nativeBuildInputs = with pkgs; [
    meson ninja pkg-config cmake
    wayland-scanner
    wrapGAppsHook3
    glib                      # per glib-compile-resources
  ];

  buildInputs = [ wayfireDev ] ++ (with pkgs; [
    # wf-shell master è passato a GTK4: il meson chiede gtkmm-4.0.
    # La versione 0.10 di nixpkgs usa ancora GTK3 — nel repository esiste
    # infatti un ramo "gtk3" separato. Questa è una delle ragioni per cui
    # il pacchetto di nixpkgs non sarebbe comunque riutilizzabile.
    gtkmm4
    gtk4
    gtk4-layer-shell

    # Elenco ricavato leggendo meson.build dei sorgenti, invece di
    # scoprirle una per volta a ogni tentativo di compilazione.
    libepoxy                  # epoxy
    libdbusmenu                # dbusmenu-glib-0.4
    libxkbcommon              # xkbregistry
    openssl
    libdrm
    libgbm                    # gbm.h (attributo nix: libgbm, pname mesa-libgbm)
    pipewire                  # libpipewire-0.3 e wireplumber: widget mixer
    wireplumber
    ddcutil                   # controllo luminosità via DDC
    yyjson                    # richiesto dal sottoprogetto wf-json

    # glm serve perché gli header pubblici di Wayfire lo includono
    # (wayfire/config/types.hpp:4), ma il suo wayfire.pc NON lo dichiara
    # fra i Requires: chi usa quegli header non se lo vede arrivare e la
    # compilazione fallisce con «glm/vec4.hpp: No such file or directory».
    # Annotato in TODO.md come possibile difetto da segnalare a monte.
    glm
    alsa-lib
    pulseaudio
    pam                       # il blocco schermo di wf-shell lo richiede
    wayland
    wayland-protocols
    libxkbcommon
  ]);

  meta = with lib; {
    description = "Pannello, sfondo e dock di Wayfire, compilati contro la nostra build";
    platforms = platforms.linux;
  };
}

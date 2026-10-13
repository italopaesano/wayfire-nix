# WCM — Wayfire Config Manager: il pannello di configurazione grafico.
#
# Compilato dai sorgenti di GitHub e NON dal pacchetto nixpkgs, che è fermo
# alla 0.10.0. Il motivo non è il gusto dell'aggiornamento: i plugin e gli
# strumenti di Wayfire sono legati alla sua ABI, e il compositore RIFIUTA
# quelli compilati per una versione diversa (src/core/plugin-loader.cpp:110,
# "API/ABI version mismatch"). Noi eseguiamo 0.12.0 master, quindi serve
# roba compilata contro quella.
# Richiede wf-shell: il suo meson si interrompe con «Dependency "wf-shell"
# not found». Va quindi compilato DOPO quello.
{ pkgs ? import <nixpkgs> { }
, wayfireDev                       # il nostro Wayfire 0.12.0
, wfShell                          # il nostro wf-shell, non quello di nixpkgs
, rev ? "872077c5f489021f68aee0038b7a533902d6f7c0"   # master al 2026-10-13
}:

let
  lib = pkgs.lib;

  sorgenti = builtins.fetchGit {
    url = "https://github.com/WayfireWM/wcm.git";
    inherit rev;
    # il rev è fissato, quindi la fetch è riproducibile
    allRefs = true;
  };
in
pkgs.stdenv.mkDerivation {
  pname = "wcm-dev";
  version = "git-${builtins.substring 0 8 rev}";
  src = sorgenti;

  nativeBuildInputs = with pkgs; [
    meson ninja pkg-config
    wayland-scanner
    wrapGAppsHook3
  ];

  buildInputs = [ wayfireDev wfShell ] ++ (with pkgs; [
    # glm: gli header di Wayfire lo includono ma wayfire.pc non lo dichiara
    glm
    gtkmm3
    gtk3
    libevdev
    fmt                       # libreria di formattazione, richiesta da src/meson.build
    libxml2
    libxkbcommon
    wayland
    wayland-protocols
  ]);

  meta = with lib; {
    description = "Pannello di configurazione grafico di Wayfire, compilato contro la nostra build";
    mainProgram = "wcm";
    platforms = platforms.linux;
  };
}

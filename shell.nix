# Ambiente di build per Wayfire (master), con wlroots, wf-config e gli altri
# sottoprogetti compilati da submodule. Gli script in scripts/ lo usano da soli.
{ pkgs ? import <nixpkgs> { } }:

let
  # Serve solo per ereditare le dipendenze di build di wlroots 0.20;
  # la libreria effettivamente usata è quella del submodule.
  wlrootsRef = pkgs.wlroots_0_20 or pkgs.wlroots;
in
pkgs.mkShell {
  inputsFrom = [ pkgs.wayfire wlrootsRef ];

  packages = with pkgs; [
    meson ninja pkg-config cmake
    wayland-scanner
    git gdb
    foot              # terminale per i test nested
    wlr-randr wayland-utils
    # uncrustify NON da nixpkgs: la CI upstream usa un fork 0.71 (scripts/style.sh)
  ];

  shellHook = ''
    export WF_DEV_ROOT=${toString ./.}
  '';
}

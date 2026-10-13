{
  description = "Wayfire di sviluppo con la correzione del cubo per i dispositivi di puntamento assoluti";

  # Perche' un flake e non il nostro solito shell.nix: il flake FISSA le
  # versioni di tutto (nixpkgs compreso) dentro flake.lock. Portando questa
  # cartella su un'altra macchina si ottiene esattamente la stessa build,
  # senza dipendere dal canale nixpkgs installato li'.
  #
  # Uso tipico sul portatile di prova:
  #   nix build .#wayfire          costruisce il compositore con la patch
  #   ./result/bin/wayfire -c <config>
  #   nix develop                  entra nell'ambiente di compilazione
  #
  # I flake richiedono che siano abilitate le funzionalita' sperimentali:
  #   experimental-features = nix-command flakes
  # (gia' attive sulla macchina di Italo).

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # I sorgenti di Wayfire presi da upstream e FISSATI a un commit preciso:
    # lo stesso su cui abbiamo sviluppato e verificato la correzione.
    # submodules = true e' indispensabile: wlroots, wf-config, wf-utils,
    # wf-touch e wf-json sono sottomoduli git e la build li compila.
    wayfire-src = {
      url = "git+https://github.com/WayfireWM/wayfire.git?ref=master&rev=fdf8832e4263db54e2fef2abf30326e16877b8a2&submodules=1";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, wayfire-src }:
    let
      sistemi = [ "x86_64-linux" "aarch64-linux" ];
      perSistema = f: nixpkgs.lib.genAttrs sistemi (s: f (import nixpkgs { system = s; }));
    in
    {
      packages = perSistema (pkgs:
        let
          wlrootsRef = pkgs.wlroots_0_20 or pkgs.wlroots;

          # Stesso criterio di vm/wayfire-dev.nix: si riusano le dipendenze
          # dei pacchetti esistenti invece di elencarle a mano, comprese le
          # PROPAGATE — e' li' che sta cairo, e senza di esse la build
          # fallisce con «Dependency "cairo" not found».
          fonti = [ pkgs.wayfire wlrootsRef ];
          deps = cat: pkgs.lib.concatMap (p: p.${cat} or [ ]) fonti;
        in
        rec {
          default = wayfire;

          wayfire = pkgs.stdenv.mkDerivation {
            pname = "wayfire-cube-absolute-pointer";
            version = "0.12.0-fdf8832e+patch";
            src = wayfire-src;

            # La correzione viene applicata come patch sopra i sorgenti
            # upstream: cosi' il flake non dipende da un fork pubblicato e
            # resta chiaro cosa e' nostro e cosa no.
            patches = [ ./patches/cube-absolute-pointer.patch ];

            nativeBuildInputs = deps "nativeBuildInputs"
              ++ deps "propagatedNativeBuildInputs"
              ++ (with pkgs; [ meson ninja pkg-config cmake wayland-scanner ]);

            buildInputs = deps "buildInputs" ++ deps "propagatedBuildInputs"
              # glm e udev non compaiono fra le dipendenze del wayfire di
              # nixpkgs (fermo alla 0.10) ma il meson di master le richiede.
              ++ (with pkgs; [ glm udev ]);

            mesonFlags = [
              "-Duse_system_wlroots=disabled"
              "-Duse_system_wfconfig=disabled"
              "-Dtests=disabled"
            ];
            mesonBuildType = "debugoptimized";

            meta = with pkgs.lib; {
              description = "Wayfire con la correzione per la rotazione del cubo con puntatori assoluti";
              mainProgram = "wayfire";
              platforms = platforms.linux;
            };
          };
        });

      # Ambiente di compilazione, per lavorare sui sorgenti a mano.
      devShells = perSistema (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.wayfire ];
          packages = with pkgs; [ git gdb foot wlr-randr wayland-utils ];
        };
      });
    };
}

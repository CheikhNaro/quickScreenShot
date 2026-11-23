{
  description = "Polished screenshot utility for Wayland compositors built with Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs supportedSystems (system: f (import nixpkgs { inherit system; }));

      # Required at runtime. Optional integrations (noctalia, satty, gradia,
      # libnotify, kdeconnect) are detected when present in PATH.
      runtimeDeps =
        pkgs: with pkgs; [
          quickshell
          grim
          imagemagick
          wl-clipboard
        ];
    in
    {
      overlays.default = final: prev: {
        quickScreenShot = self.packages.${final.system}.default;
      };

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "quickscreenshot";
          version = "0.1.0";

          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter =
              path: type:
              let
                baseName = baseNameOf path;
              in
              !(builtins.elem baseName [
                "flake.nix"
                "flake.lock"
                ".git"
                ".gitignore"
                "README.md"
                "LICENSE"
              ]);
          };

          nativeBuildInputs = with pkgs; [
            makeWrapper
            qt6.wrapQtAppsHook
          ];

          buildInputs = with pkgs; [
            qt6.qt5compat
          ];

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/quickscreenshot
            cp -r . $out/share/quickscreenshot/

            mkdir -p $out/bin
            makeWrapper ${pkgs.quickshell}/bin/quickshell $out/bin/quickscreenshot \
              --prefix PATH : ${pkgs.lib.makeBinPath (runtimeDeps pkgs)} \
              --add-flags "-c $out/share/quickscreenshot -n"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Quickshell-based screenshot utility for Wayland compositors";
            homepage = "https://github.com/CheikhNaro/quickScreenShot";
            license = licenses.mit;
            platforms = platforms.linux;
            mainProgram = "quickscreenshot";
          };
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = runtimeDeps pkgs;
        };
      });
    };
}

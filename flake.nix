{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    fenix,
    crane,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages."${system}";
        rust = fenix.packages.${system}.complete;
        craneLib = crane.lib."${system}".overrideToolchain rust.toolchain;
        buildInputs = with pkgs; [
          alsaLib
          udev
          xorg.libXcursor
          xorg.libXi
          xorg.libXrandr
          libxkbcommon
          vulkan-loader
          wayland
        ];
        nativeBuildInputs = with pkgs; [
          mold
          pkg-config
        ];
      in {
        packages.conway_multiplayer-bin = craneLib.buildPackage {
          name = "conway_multiplayer-bin";
          src = craneLib.cleanCargoSource ./.;
          inherit buildInputs;
          inherit nativeBuildInputs;
        };

        packages.conway_multiplayer-assets = pkgs.stdenv.mkDerivation {
          name = "conway_multiplayer-assets";
          src = ./assets;
          phases = ["unpackPhase" "installPhase"];
          installPhase = ''
            mkdir -p $out
            cp -r $src $out/assets
          '';
        };

        packages.conway_multiplayer = pkgs.stdenv.mkDerivation {
          name = "conway_multiplayer";
          phases = ["installPhase"];
          installPhase = ''
            mkdir -p $out
            ln -s ${self.packages.${system}.conway_multiplayer-assets}/assets $out/assets
            cp ${self.packages.${system}.conway_multiplayer-bin}/lib/conway_multiplayer $out/conway_multiplayer
          '';
        };

        packages.conway_multiplayer-wasm = let
          target = "wasm32-unknown-unknown";
          toolchainWasm = with fenix.packages.${system};
            combine [
              complete.rustc
              complete.cargo
              targets.${target}.latest.rust-std
            ];
          craneWasm = crane.lib.${system}.overrideToolchain toolchainWasm;
        in
          craneWasm.buildPackage {
            src = craneLib.cleanCargoSource ./.;
            CARGO_BUILD_TARGET = target;
            CARGO_PROFILE = "release";
            inherit nativeBuildInputs;
            doCheck = false;
          };

        packages.conway_multiplayer-web = pkgs.stdenv.mkDerivation {
          name = "conway_multiplayer-web";
          src = ./web;
          nativeBuildInputs = [
            pkgs.wasm-bindgen-cli
            pkgs.binaryen
          ];
          phases = ["unpackPhase" "installPhase"];
          installPhase = ''
            mkdir -p $out
            wasm-bindgen --out-dir $out --out-name conway_multiplayer --target web ${self.packages.${system}.conway_multiplayer-wasm}/lib/conway_multiplayer.wasm
            mv $out/conway_multiplayer_bg.wasm .
            wasm-opt -Oz -o $out/conway_multiplayer_bg.wasm conway_multiplayer_bg.wasm
            cp * $out/
            ln -s ${self.packages.${system}.conway_multiplayer-assets}/assets $out/assets
          '';
        };

        packages.conway_multiplayer-web-server = pkgs.writeShellScriptBin "conway_multiplayer-web-server" ''
          ${pkgs.simple-http-server}/bin/simple-http-server -i -c=html,wasm,ttf,js -- ${self.packages.${system}.conway_multiplayer-web}/
        '';

        defaultPackage = self.packages.${system}.conway_multiplayer;

        apps.conway_multiplayer = flake-utils.lib.mkApp {
          drv = self.packages.${system}.conway_multiplayer;
          exePath = "/conway_multiplayer";
        };

        apps.conway_multiplayer-web-server = flake-utils.lib.mkApp {
          drv = self.packages.${system}.conway_multiplayer-web-server;
          exePath = "/bin/conway_multiplayer-web-server";
        };

        defaultApp = self.apps.${system}.conway_multiplayer;

        checks = {
          pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks = {
              alejandra.enable = true;
              statix.enable = true;
              rustfmt.enable = true;
              clippy = {
                enable = false;
                entry = let
                  rust-clippy = rust-clippy.withComponents ["clippy"];
                in
                  pkgs.lib.mkForce "${rust-clippy}/bin/cargo-clippy clippy";
              };
            };
          };
        };

        devShell = pkgs.mkShell {
          shellHook = ''
            export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.lib.makeLibraryPath buildInputs}"
            ${self.checks.${system}.pre-commit-check.shellHook}
          '';
          inherit buildInputs;
          nativeBuildInputs =
            [
              (rust.withComponents ["cargo" "rustc" "rust-src" "rustfmt" "clippy"])
            ]
            ++ nativeBuildInputs;
        };
      }
    );
}

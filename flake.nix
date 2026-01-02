{
  description = "Logos Chat Module - A chat plugin for Logos using Waku";

  inputs = {
    # Follow the same nixpkgs as logos-liblogos to ensure compatibility
    nixpkgs.follows = "logos-liblogos/nixpkgs";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos.url = "github:logos-co/logos-liblogos";
    logos-waku-module.url = "github:logos-co/logos-waku-module?ref=logos-testnet-demo";
    #logos-waku-module.url = "path:/Users/prem/Code/logos-waku-module";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-liblogos, logos-waku-module }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosLiblogos = logos-liblogos.packages.${system}.default;
        logosWakuModule = logos-waku-module.packages.${system}.default;
      });
    in
    {
      packages = forAllSystems ({ pkgs, logosSdk, logosLiblogos, logosWakuModule }: 
        let
          # Common configuration
          common = import ./nix/default.nix { 
            inherit pkgs logosSdk logosLiblogos; 
          };
          src = ./.;
          
          # Library package
          lib = import ./nix/lib.nix { 
            inherit pkgs common src logosWakuModule logosSdk; 
          };

          # Include package (generated headers from plugin)
          include = import ./nix/include.nix {
            inherit pkgs common src lib logosSdk;
          };

          # Combined package
          combined = pkgs.symlinkJoin {
            name = "logos-chat-module";
            paths = [ lib include ];
          };
        in
        {
          # Individual outputs
          logos-chat-module-lib = lib;
          logos-chat-module-include = include;
          
          # Default package (combined)
          default = combined;
        }
      );

      devShells = forAllSystems ({ pkgs, logosSdk, logosLiblogos, logosWakuModule }: {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
          ];
          buildInputs = [
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.zstd
            pkgs.krb5
            pkgs.protobuf
            pkgs.abseil-cpp
          ];
          
          shellHook = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_ROOT="${logosLiblogos}"
            echo "Logos Chat Module development environment"
            echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
            echo "LOGOS_LIBLOGOS_ROOT: $LOGOS_LIBLOGOS_ROOT"
          '';
        };
      });
    };
}


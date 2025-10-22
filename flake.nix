{
  description = "Logos Chat Module - Chat capabilities with protobuf messaging support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos.url = "github:logos-co/logos-liblogos";
    logos-waku-module.url = "git+ssh://git@github.com/logos-co/logos-waku-module.git";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-liblogos, logos-waku-module }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosLiblogos = logos-liblogos.packages.${system}.default;
        logosWaku = logos-waku-module.packages.${system}.default;
      });
    in
    {
      packages = forAllSystems ({ pkgs, logosSdk, logosLiblogos, logosWaku }: {
        default = pkgs.stdenv.mkDerivation rec {
          pname = "logos-chat-module";
          version = "1.0.0";
          
          src = ./.;
          
          nativeBuildInputs = [ 
            pkgs.cmake 
            pkgs.ninja 
            pkgs.pkg-config
            pkgs.qt6.wrapQtAppsNoGuiHook
            pkgs.protobuf
          ];
          
          buildInputs = [ 
            pkgs.qt6.qtbase 
            pkgs.qt6.qtremoteobjects 
            pkgs.protobuf
            pkgs.abseil-cpp
            logosSdk
            logosLiblogos
          ];
          
          cmakeFlags = [ 
            "-GNinja"
            "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
            "-DLOGOS_LIBLOGOS_ROOT=${logosLiblogos}"
            "-DLOGOS_CHAT_MODULE_USE_VENDOR=OFF"
          ];
          
          # Set environment variables for CMake to find the dependencies
          LOGOS_CPP_SDK_ROOT = "${logosSdk}";
          LOGOS_LIBLOGOS_ROOT = "${logosLiblogos}";
          
          meta = with pkgs.lib; {
            description = "Logos Chat Module - Provides chat capabilities with protobuf messaging support";
            platforms = platforms.unix;
          };
        };
      });

      devShells = forAllSystems ({ pkgs, logosSdk, logosLiblogos, logosWaku }: {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.protobuf
          ];
          buildInputs = [
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.protobuf
            pkgs.abseil-cpp
            logosSdk
            logosLiblogos
          ];
          
          shellHook = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_ROOT="${logosLiblogos}"
            export LOGOS_WAKU_MODULE_ROOT="${logosWaku}"
            echo "Logos Chat Module development environment"
            echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
            echo "LOGOS_LIBLOGOS_ROOT: $LOGOS_LIBLOGOS_ROOT"
            echo "LOGOS_WAKU_MODULE_ROOT: $LOGOS_WAKU_MODULE_ROOT"
          '';
        };
      });
    };
}

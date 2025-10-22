{
  description = "Logos Chat Module - Chat capabilities with protobuf messaging support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos.url = "github:logos-co/logos-liblogos";
    logos-waku-module.url = "git+ssh://git@github.com/logos-co/logos-waku-module.git?ref=update_flake&rev=fb6dc746d0c8885c3467feedbf252bd7858411c0";
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
        default = pkgs.symlinkJoin {
          name = "logos-chat-module-deps";
          paths = [
            logosSdk
            logosLiblogos
            logosWaku
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.protobuf
            pkgs.abseil-cpp
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
          ];
          
          postBuild = ''
            mkdir -p $out/env
            cat > $out/env/setup.sh << 'EOF'
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_ROOT="${logosLiblogos}"
            export LOGOS_WAKU_MODULE_ROOT="${logosWaku}"
            export CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH:${logosSdk}:${logosLiblogos}:${logosWaku}"
            EOF
          '';
          
          meta = with pkgs.lib; {
            description = "Logos Chat Module dependencies bundle";
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

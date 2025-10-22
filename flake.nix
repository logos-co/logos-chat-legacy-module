{
  description = "Logos Test Example - Pulls and compiles logos-liblogos, logos-package-manager, and logos-capability-module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    logos-liblogos.url = "git+ssh://git@github.com/logos-co/logos-liblogos.git";
    logos-cpp-sdk.url = "git+ssh://git@github.com/logos-co/logos-cpp-sdk.git";
    #logos-package-manager.url = "path:/Users/iurimatias/Projects/Logos/LogosCore/logos-package-manager";
    logos-package-manager.url = "git+ssh://git@github.com/logos-co/logos-package-manager.git";
    logos-capability-module.url = "git+ssh://git@github.com/logos-co/logos-capability-module.git";
    logos-waku-module.url = "git+ssh://git@github.com/logos-co/logos-waku-module.git?ref=update_flake";
  };

  outputs = { self, nixpkgs, logos-liblogos, logos-cpp-sdk, logos-package-manager, logos-capability-module, logos-waku-module }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
        liblogos = logos-liblogos.packages.${system}.default;
        cppSdk = logos-cpp-sdk.packages.${system}.default;
        packageManager = logos-package-manager.packages.${system}.default;
        capabilityModule = logos-capability-module.packages.${system}.default;
        wakuModule = logos-waku-module.packages.${system}.default;
      });
    in
    {
      packages = forAllSystems ({ pkgs, liblogos, cppSdk, packageManager, capabilityModule, wakuModule }: {
        default = pkgs.stdenv.mkDerivation rec {
          pname = "logos-test-example";
          version = "1.0.0";
          
          src = ./.;

          # This is an aggregate runtime layout; avoid stripping to prevent hook errors
          dontStrip = true;
          
          nativeBuildInputs = [ 
            pkgs.cmake 
            pkgs.ninja 
            pkgs.pkg-config
            pkgs.qt6.wrapQtAppsHook
            pkgs.qt6.wrapQtAppsNoGuiHook
          ];
          
          buildInputs = [ 
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.zstd
            pkgs.krb5
            liblogos
            cppSdk
            wakuModule
          ];

          qtLibPath = pkgs.lib.makeLibraryPath [
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.zstd
            pkgs.krb5
            pkgs.zlib
            pkgs.glib
            pkgs.stdenv.cc.cc
          ];
          qtPluginPath = "${pkgs.qt6.qtbase}/lib/qt-6/plugins";

          qtWrapperArgs = [
            "--prefix" "LD_LIBRARY_PATH" ":" qtLibPath
            "--prefix" "QT_PLUGIN_PATH" ":" qtPluginPath
          ];
          
          # Configure and build phase
          configurePhase = ''
            runHook preConfigure
            
            echo "Configuring logos-test-example..."
            echo "liblogos: ${liblogos}"
            echo "cpp-sdk: ${cppSdk}"
            echo "package-manager: ${packageManager}"
            echo "capability-module: ${capabilityModule}"
            echo "waku-module: ${wakuModule}"
            
            # Verify that the built components exist
            test -d "${liblogos}" || (echo "liblogos not found" && exit 1)
            test -d "${cppSdk}" || (echo "cpp-sdk not found" && exit 1)
            test -d "${packageManager}" || (echo "package-manager not found" && exit 1)
            test -d "${capabilityModule}" || (echo "capability-module not found" && exit 1)
            test -d "${wakuModule}" || (echo "waku-module not found" && exit 1)
            
            cmake -S . -B build \
              -GNinja \
              -DCMAKE_BUILD_TYPE=Release \
              -DLOGOS_LIBLOGOS_ROOT=${liblogos} \
              -DLOGOS_CPP_SDK_ROOT=${cppSdk}
            
            runHook postConfigure
          '';
          
          buildPhase = ''
            runHook preBuild
            
            cmake --build build
            echo "logos-test-example built successfully!"
            
            runHook postBuild
          '';
          
          installPhase = ''
            set -euo pipefail
            mkdir -p $out
            echo "Logos Test Example - All components compiled successfully" > $out/README.txt
            echo "liblogos: ${liblogos}" >> $out/README.txt
            echo "cpp-sdk: ${cppSdk}" >> $out/README.txt
            echo "package-manager: ${packageManager}" >> $out/README.txt
            echo "capability-module: ${capabilityModule}" >> $out/README.txt
            echo "waku-module: ${wakuModule}" >> $out/README.txt

            # Prepare runtime layout
            mkdir -p "$out/bin" "$out/lib" "$out/bin/modules" "$out/modules"
            
            # Install our custom binary
            if [ -f "build/bin/logos-test-example" ]; then
              cp build/bin/logos-test-example "$out/bin/"
              echo "Installed logos-test-example binary"
            fi
            
            # Also copy the original binaries from liblogos for reference
            if [ -f "${liblogos}/bin/logoscore" ]; then
              cp -L "${liblogos}/bin/logoscore" "$out/bin/logoscore"
            fi
            if [ -f "${liblogos}/bin/logos_host" ]; then
              cp -L "${liblogos}/bin/logos_host" "$out/bin/logos_host"
            fi

            # Copy core shared library to lib for RPATH resolution
            if ls "${liblogos}/lib/"liblogos_core.* >/dev/null 2>&1; then
              cp -L "${liblogos}/lib/"liblogos_core.* "$out/lib/" || true
            fi

            # Copy libwaku library to modules directory alongside the plugin
            if ls "${wakuModule}/lib/logos/modules/"libwaku.* >/dev/null 2>&1; then
              cp -L "${wakuModule}/lib/logos/modules/"libwaku.* "$out/bin/modules/" || true
              cp -L "${wakuModule}/lib/logos/modules/"libwaku.* "$out/modules/" || true
            fi

            # Determine platform-specific plugin extension
            OS_EXT="so"
            case "$(uname -s)" in
              Darwin)
                OS_EXT="dylib";;
              Linux)
                OS_EXT="so";;
              MINGW*|MSYS*|CYGWIN*)
                OS_EXT="dll";;
            esac

            # Symlink plugins into both expected locations
            ln -s "${packageManager}/lib/logos/modules/package_manager_plugin.$OS_EXT" "$out/bin/modules/package_manager_plugin.$OS_EXT" || true
            ln -s "${capabilityModule}/lib/logos/modules/capability_module_plugin.$OS_EXT" "$out/bin/modules/capability_module_plugin.$OS_EXT" || true
            ln -s "${wakuModule}/lib/logos/modules/waku_module_plugin.$OS_EXT" "$out/bin/modules/waku_module_plugin.$OS_EXT" || true
            ln -s "${packageManager}/lib/logos/modules/package_manager_plugin.$OS_EXT" "$out/modules/package_manager_plugin.$OS_EXT" || true
            ln -s "${capabilityModule}/lib/logos/modules/capability_module_plugin.$OS_EXT" "$out/modules/capability_module_plugin.$OS_EXT" || true
            ln -s "${wakuModule}/lib/logos/modules/waku_module_plugin.$OS_EXT" "$out/modules/waku_module_plugin.$OS_EXT" || true

            # Helpful message
            echo "Installed runtime to $out"
            echo " - binaries in $out/bin"
            echo " - core lib in $out/lib"
            echo " - plugins in $out/bin/modules and $out/modules"

            # Ensure the subsequent fixup hooks run without nounset interfering
            set +u
          '';
          
          meta = with pkgs.lib; {
            description = "Logos Test Example - Pulls and compiles logos-liblogos, logos-package-manager, and logos-capability-module";
            platforms = platforms.unix;
          };
        };
        
        # Individual packages for direct access
        liblogos = liblogos;
        package-manager = packageManager;
        capability-module = capabilityModule;
        waku-module = wakuModule;
      });

      devShells = forAllSystems ({ pkgs, liblogos, cppSdk, packageManager, capabilityModule, wakuModule }: {
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
            liblogos
            cppSdk
            packageManager
            capabilityModule
            wakuModule
          ];
          
          shellHook = ''
            export LOGOS_LIBLOGOS_ROOT="${liblogos}"
            export LOGOS_CPP_SDK_ROOT="${cppSdk}"
            export LOGOS_PACKAGE_MANAGER_ROOT="${packageManager}"
            export LOGOS_CAPABILITY_MODULE_ROOT="${capabilityModule}"
            export LOGOS_WAKU_MODULE_ROOT="${wakuModule}"

            qt_ld_path="${pkgs.lib.makeLibraryPath [
              pkgs.qt6.qtbase
              pkgs.qt6.qtremoteobjects
              pkgs.zstd
              pkgs.krb5
              pkgs.zlib
              pkgs.glib
              pkgs.stdenv.cc.cc
            ]}"
            prev_ld_library_path="''${LD_LIBRARY_PATH-}"
            if [ -n "$prev_ld_library_path" ]; then
              export LD_LIBRARY_PATH="$qt_ld_path:$prev_ld_library_path"
            else
              export LD_LIBRARY_PATH="$qt_ld_path"
            fi

            qt_plugin_path="${pkgs.qt6.qtbase}/lib/qt-6/plugins"
            prev_qt_plugin_path="''${QT_PLUGIN_PATH-}"
            if [ -n "$prev_qt_plugin_path" ]; then
              export QT_PLUGIN_PATH="$qt_plugin_path:$prev_qt_plugin_path"
            else
              export QT_PLUGIN_PATH="$qt_plugin_path"
            fi
            echo "Logos Test Example development environment"
            echo "LOGOS_LIBLOGOS_ROOT: $LOGOS_LIBLOGOS_ROOT"
            echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
            echo "LOGOS_PACKAGE_MANAGER_ROOT: $LOGOS_PACKAGE_MANAGER_ROOT"
            echo "LOGOS_CAPABILITY_MODULE_ROOT: $LOGOS_CAPABILITY_MODULE_ROOT"
            echo "LOGOS_WAKU_MODULE_ROOT: $LOGOS_WAKU_MODULE_ROOT"

            # Prepare module directories for runtime discovery
            mkdir -p "$PWD/bin/modules" "$PWD/modules"

            # Determine platform-specific library extension
            OS_EXT="so"
            case "$(uname -s)" in
              Darwin)
                OS_EXT="dylib";;
              Linux)
                OS_EXT="so";;
              MINGW*|MSYS*|CYGWIN*)
                OS_EXT="dll";;
            esac

            # Symlink the plugins and libwaku into expected locations
            for targetDir in "$PWD/bin/modules" "$PWD/modules"; do
              mkdir -p "$targetDir"
              ln -sf "$LOGOS_PACKAGE_MANAGER_ROOT/lib/logos/modules/package_manager_plugin.$OS_EXT" "$targetDir/package_manager_plugin.$OS_EXT" 2>/dev/null || true
              ln -sf "$LOGOS_CAPABILITY_MODULE_ROOT/lib/logos/modules/capability_module_plugin.$OS_EXT" "$targetDir/capability_module_plugin.$OS_EXT" 2>/dev/null || true
              ln -sf "$LOGOS_WAKU_MODULE_ROOT/lib/logos/modules/waku_module_plugin.$OS_EXT" "$targetDir/waku_module_plugin.$OS_EXT" 2>/dev/null || true
              # Also symlink libwaku library to modules directory
              if ls "$LOGOS_WAKU_MODULE_ROOT/lib/logos/modules/"libwaku.* >/dev/null 2>&1; then
                ln -sf "$LOGOS_WAKU_MODULE_ROOT/lib/logos/modules/"libwaku.* "$targetDir/" 2>/dev/null || true
              fi
            done

            echo "Symlinked plugins into ./bin/modules and ./modules"
          '';
        };
      });
    };
}

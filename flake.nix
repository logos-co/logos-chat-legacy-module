{
  description = "Logos Waku Module - Pulls and compiles logos-liblogos, logos-package-manager, and logos-capability-module";

  inputs = {
    # Follow the same nixpkgs as logos-liblogos to ensure compatibility
    nixpkgs.follows = "logos-liblogos/nixpkgs";
    logos-liblogos.url = "github:logos-co/logos-liblogos";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-package-manager.url = "github:logos-co/logos-package-manager";
    logos-capability-module.url = "github:logos-co/logos-capability-module";
    logos-waku-module.url = "github:logos-co/logos-waku-module";
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
          pname = "logos-chat-module";
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
            pkgs.protobuf
            pkgs.abseil-cpp
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
            
            echo "Configuring logos-chat-module..."
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
            
            
            # Create a temporary directory for generated files and modules
            mkdir -p "$PWD/generated"
            mkdir -p "$PWD/temp_modules"
            mkdir -p "$PWD/cpp_sdk_src"
            export GENERATED_SDK_DIR="$PWD/generated"
            
            # Check if cpp-sdk headers are available
            if [ ! -f "${cppSdk}/include/logos_api.h" ]; then
              echo "Warning: cpp-sdk headers not found at ${cppSdk}/include/"
              echo "Checking for headers in other locations..."
              
              # Check if headers exist in the cpp-sdk package
              find "${cppSdk}" -name "logos_api.h" 2>/dev/null || echo "logos_api.h not found in cpp-sdk package"
              
              # List what's actually in the cpp-sdk package
              echo "Contents of cpp-sdk package:"
              ls -la "${cppSdk}/" || true
              ls -la "${cppSdk}/include/" 2>/dev/null || echo "No include directory"
              ls -la "${cppSdk}/lib/" 2>/dev/null || echo "No lib directory"
            else
              echo "Found cpp-sdk headers at ${cppSdk}/include/"
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
            
            # Symlink dependency plugins to temp directory for generator
            ln -s "${packageManager}/lib/logos/modules/package_manager_plugin.$OS_EXT" "$PWD/temp_modules/package_manager_plugin.$OS_EXT" || true
            ln -s "${capabilityModule}/lib/logos/modules/capability_module_plugin.$OS_EXT" "$PWD/temp_modules/capability_module_plugin.$OS_EXT" || true
            
            # Copy libwaku to temp directory
            if ls "${wakuModule}/lib/logos/modules/"libwaku.* >/dev/null 2>&1; then
              cp -L "${wakuModule}/lib/logos/modules/"libwaku.* "$PWD/temp_modules/" || true
            fi
            
            # Copy and fix waku plugin (can't symlink because we need to modify it)
            if [ -f "${wakuModule}/lib/logos/modules/waku_module_plugin.$OS_EXT" ]; then
              cp "${wakuModule}/lib/logos/modules/waku_module_plugin.$OS_EXT" "$PWD/temp_modules/waku_module_plugin.$OS_EXT"
              
              # Fix the library path on macOS before running the generator
              if [ "$(uname -s)" = "Darwin" ]; then
                if command -v install_name_tool >/dev/null 2>&1; then
                  # Find the correct libwaku path in temp directory
                  WAKU_LIB_PATH=$(find "$PWD/temp_modules" -name "libwaku.*" -type f | head -1)
                  if [ -n "$WAKU_LIB_PATH" ]; then
                    echo "Fixing waku_module_plugin to use libwaku at: $WAKU_LIB_PATH"
                    
                    # Check and fix library references
                    echo "Current library references in waku_module_plugin:"
                    otool -L "${wakuModule}/lib/logos/modules/waku_module_plugin.$OS_EXT" | grep libwaku || echo "No libwaku references found"
                    
                    # Try to fix any libwaku references that don't point to the Nix store
                    otool -L "${wakuModule}/lib/logos/modules/waku_module_plugin.$OS_EXT" | grep libwaku | while read line; do
                      OLD_PATH=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
                      if [[ "$OLD_PATH" != /nix/store/* ]]; then
                        echo "Fixing library reference: $OLD_PATH -> $WAKU_LIB_PATH"
                        install_name_tool -change "$OLD_PATH" "$WAKU_LIB_PATH" "$PWD/temp_modules/waku_module_plugin.$OS_EXT" || true
                      fi
                    done
                  fi
                fi
              fi
            fi
            
            # Run cpp generator BEFORE cmake to generate SDK wrappers
            echo "Running cpp generator on metadata.json..."
            echo "Temp module directory contents:"
            ls -la "$PWD/temp_modules/"
            "${cppSdk}/bin/logos-cpp-generator" --metadata ./metadata.json --module-dir "$PWD/temp_modules"
            
            # Copy generated files to the generated directory for cmake to find
            echo "Copying generated files..."
            if [ -d "./logos-cpp-sdk/cpp/generated" ]; then
              cp -r "./logos-cpp-sdk/cpp/generated"/* "$PWD/generated/" || true
              echo "Generated SDK files:"
              ls -la "$PWD/generated/"
            fi
            
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
            echo "logos-chat-module built successfully!"
            
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/lib
            
            # Install our chat plugin library
            if [ -f "build/modules/chat_plugin.dylib" ] || [ -f "build/modules/chat_plugin.so" ]; then
              cp build/modules/chat_plugin.* "$out/lib/" 2>/dev/null || true
              echo "Installed chat_plugin library to $out/lib/"
            else
              echo "Warning: chat_plugin library not found"
            fi
            
            runHook postInstall
          '';
          
          meta = with pkgs.lib; {
            description = "Logos Chat Module - A chat plugin for Logos using Waku";
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
            echo "Logos Waku Module development environment"
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

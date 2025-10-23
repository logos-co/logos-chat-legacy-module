# Builds the logos-chat-module library
{ pkgs, common, src }:

pkgs.stdenv.mkDerivation {
  pname = "${common.pname}-lib";
  version = common.version;
  
  inherit src;
  inherit (common) nativeBuildInputs buildInputs cmakeFlags meta env;
  
  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/lib
    # Find and copy the built library file from the modules directory
    if [ -f modules/chat_plugin.dylib ]; then
      cp modules/chat_plugin.dylib $out/lib/
    elif [ -f modules/chat_plugin.so ]; then
      cp modules/chat_plugin.so $out/lib/
    else
      echo "Error: No library file found"
      exit 1
    fi
    
    runHook postInstall
  '';
}


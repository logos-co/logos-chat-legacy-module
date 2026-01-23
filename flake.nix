{
  description = "Logos Chat Module - A chat plugin for Logos using Waku";

  inputs = {
    # Use local path for development, change to github:logos-co/logos-module-builder for release
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    #logos-module-builder.url = "path:/Users/iurimatias/Projects/Logos/logos-module-builder";
    nixpkgs.follows = "logos-module-builder/nixpkgs";
    logos-waku-module.url = "github:logos-co/logos-waku-module";
  };

  outputs = { self, logos-module-builder, nixpkgs, logos-waku-module }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./module.yaml;
      moduleInputs = {
        waku_module = logos-waku-module;
      };
    };
}

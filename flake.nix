{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";

  outputs = { nixpkgs, flake-utils, ... }:
    (
      (flake-utils.lib.eachDefaultSystem (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          packages.default = pkgs.callPackage ./default.nix { };
        }))
      //
      {
        nixosModules.default = import ./module.nix;
      }
    );
}


{
  inputs = {
    flake-compat = {
      url = "github:lheckemann/flake-compat/add-overrideInputs";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.3.0";
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    toplevel@{ config, ... }: {
    systems = ["x86_64-linux" "aarch64-linux"];
    perSystem = { config, pkgs, self', ... }: {
      packages = {
        shim-unsigned = pkgs.shim-unsigned.override {
          vendorCertFile = ./pki/snakeoil-vendor-cert.pem;
        };
        # TODO: put it in passthru for shimx64.efi
        shim-signed = pkgs.runCommand "sign-shim" {} ''
          mkdir -p $out/share/shim
          ${pkgs.sbsigntool}/bin/sbsign \
            --key ${./pki/snakeoil-db-uefi.key} \
            --cert ${./pki/snakeoil-db-uefi.pem} \
            --output $out/share/shim/shimx64.efi \
            ${self'.packages.shim-unsigned}/share/shim/shimx64.efi
        '';
      };
    };
  });
}

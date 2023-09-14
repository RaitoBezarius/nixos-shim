{ nixpkgs ? <nixpkgs> }:
let pkgs = import nixpkgs {};
in rec {
  shim-unsigned = pkgs.shim-unsigned.override {
    vendorCertFile = ./pki/snakeoil-vendor-cert.pem;
  };
  # TODO: put it in passthru for shimx64.efi
  shim-signed = pkgs.runCommand "sign-shim" {} ''
    mkdir -p $out/share/shim
    ${pkgs.sbsigntool}/bin/sbsign --key ${./pki/snakeoil-db-uefi.key} --cert ${./pki/snakeoil-db-uefi.pem} --output $out/share/shim/shimx64.efi ${shim-unsigned}/share/shim/shimx64.efi
  '';
}

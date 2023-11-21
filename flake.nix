{
  inputs = {
    flake-compat = {
      url = "github:lheckemann/flake-compat/add-overrideInputs";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:lheckemann/nixpkgs/shim";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.3.0";
    # Work around OVMF with broken secure boot
    nixpkgs-old.url = github:nixos/nixpkgs/8f40f2f90b9c9032d1b824442cfbbe0dbabd0dbd;
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    toplevel@{ config, self, ... }: {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      flake.hydraJobs = {
        inherit (self) packages;
      };
      perSystem = { config, pkgs, self', system, ... }: {
        packages =
          let
            configModule = { modulesPath, pkgs, ... }: {
              imports = [
                #(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
                (modulesPath + "/installer/cd-dvd/iso-image.nix")
              ];
              secureboot = {
                signingCertificate = ./pki/snakeoil-vendor-cert.pem;
                # TODO: use hardware module or something
                privateKeyFile = ./pki/snakeoil-vendor-key.pem;
                shim = "${self'.packages.shim-signed}/share/shim/shimx64.efi";
              };
              # for faster build
              isoImage.squashfsCompression = "zstd -Xcompression-level 6";
              isoImage.makeEfiBootable = true;

              users.users.root.password = "";
              environment.systemPackages = [
                pkgs.sbctl
                pkgs.sbsigntool
                pkgs.efivar
                pkgs.vim
              ];
            };
            nixos = pkgs.nixos configModule;
          in
          {
            shim-unsigned = pkgs.shim-unsigned.override {
              vendorCertFile = ./pki/snakeoil-vendor-cert.cer;
            };
            # TODO: put it in passthru for shimx64.efi
            shim-signed = pkgs.runCommand "sign-shim" { } ''
              mkdir -p $out/share/shim
              ${pkgs.sbsigntool}/bin/sbsign \
                --key ${./pki/snakeoil-db-uefi.key} \
                --cert ${./pki/snakeoil-db-uefi.pem} \
                --output $out/share/shim/shimx64.efi \
                ${self'.packages.shim-unsigned}/share/shim/shimx64.efi
            '';

            iso = nixos.config.system.build.isoImage;
            efiDir = nixos.config.system.build.efiDir;

            ovmf = (inputs.nixpkgs-old.legacyPackages.${system}.OVMF.override { secureBoot = true; }).fd;
            #ovmf = (inputs.nixpkgs.legacyPackages.${system}.OVMF.override {secureBoot = true;}).fd;

            ovmf_vars = pkgs.runCommand "OVMF_VARS.fd"
              {
                vars = ./vars.yaml;
                nativeBuildInputs = [ pkgs.python3Packages.virt-firmware ];
              } ''
              args=(
                -i ${self'.packages.ovmf}/FV/OVMF_VARS.fd
                -o $out
                --set-shim-verbose
                --enroll-redhat
                --add-db 10a62c65-007e-4c1a-a5f2-e916b35a9442 ${./pki/snakeoil-db-uefi.pem}
                --secure-boot
              )
              virt-fw-vars "''${args[@]}"
            '';

            run-iso = pkgs.writeScriptBin "run-secureboot-iso-in-qemu" ''
              args=(
                -m 2G
                -smp 4
                -cdrom ${self'.packages.iso}/iso/*.iso
                -net none
                -serial stdio
                -drive "if=pflash,format=raw,readonly=on,file=${self'.packages.ovmf}/FV/OVMF_CODE.fd"
                -drive "if=pflash,format=raw,snapshot=on,file=${self'.packages.ovmf_vars}"
              )
              qemu-kvm "''${args[@]}" "$@"
            '';
          };

        apps.default = {
          type = "app";
          program = self'.packages.run-iso;
        };
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [ uefi-run sbsigntool python3Packages.virt-firmware ];
          ovmf = self'.packages.ovmf;
          inherit (self'.packages) ovmf_vars;
        };
      };
    }
  );
}

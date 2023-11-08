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
    systems = ["x86_64-linux" "aarch64-linux"];
    flake.hydraJobs = {
      inherit (self) packages;
    };
    perSystem = { config, pkgs, self', system, ... }: {
      packages = {
        shim-unsigned = pkgs.shim-unsigned.override {
          vendorCertFile = ./pki/snakeoil-vendor-cert.cer;
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
        test-image = pkgs.vmTools.runInLinuxVM (pkgs.runCommand "test-image" {
          nativeBuildInputs = [ pkgs.coreutils pkgs.systemd pkgs.dosfstools pkgs.mtools ];
          preVM = ''
            mkdir -p $out
            ${pkgs.vmTools.qemu}/bin/qemu-img create -f qcow2 $out/test.qcow2 500M
          '';
          memSize = "4G";
          QEMU_OPTS = "-drive file=$out/test.qcow2,if=virtio -smp 4";
        } ''
          mkdir -p esp/EFI/BOOT
          cp ${self'.packages.shim-signed}/share/shim/shimx64.efi esp/EFI/BOOT/BOOTX64.EFI

          mkdir repart.d
          cat > repart.d/table.conf <<EOF
          [Partition]
          Type=esp
          Format=vfat
          CopyFiles=$PWD/esp/EFI:/EFI
          EOF
          systemd-repart --empty=require --dry-run=no --definitions=repart.d /dev/vda
        '');
        run-test-image = pkgs.writeScriptBin "run-test-image" ''
          set -exuo pipefail
          args=(
            -m 2G -smp 4
            -bios ${self'.packages.ovmf}/FV/OVMF.fd
            -drive if=virtio,file=${self'.packages.test-image}/test.qcow2,snapshot=on
            -net none
            -cdrom ${self'.packages.iso}/iso/nixos.iso
          )
          ${pkgs.qemu_kvm}/bin/qemu-kvm "''${args[@]}"
        '';

        iso = let
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
              (pkgs.writeShellScriptBin "enroll-keys" ''
                set -exuo pipefail
                # the only key that actually matters is the db one, so generate the others
                sbctl create-keys
                # and then replace the generated db cert with our test one
                sbctl import-keys --db-cert ${./pki/snakeoil-db-uefi.pem} --db-key ${./pki/snakeoil-db-uefi.key}
                # yolo (this shouldn't be done outside test environments!)
                sbctl enroll-keys --yes-this-might-brick-my-machine
                set-shim-verbose
              '')
              (pkgs.writeShellScriptBin "set-shim-verbose" ''
                printf "\x01" >/tmp/verbose
                efivar --name 605dab50-e046-4300-abb6-3dd810dd8b23-SHIM_VERBOSE -w -f /tmp/verbose
              '')
            ];
            systemd.tmpfiles.rules = [
              "L+ /run/sbkeys - - - - ${./pki}"
            ];
          };
          nixos = pkgs.nixos configModule;
        in nixos.config.system.build.isoImage;

        ovmf = (inputs.nixpkgs-old.legacyPackages.${system}.OVMF.override {secureBoot = true;}).fd;
        #ovmf = (inputs.nixpkgs.legacyPackages.${system}.OVMF.override {secureBoot = true;}).fd;

        ovmf_vars = pkgs.runCommand "OVMF_VARS.fd" {
          vars = ./vars.yaml;
        } ''
          ${pkgs.python3Packages.ovmfvartool}/bin/ovmfvartool compile $vars $out
        '';
      };

      apps.default = {
        type = "app";
        program = pkgs.writeScriptBin "run-secureboot-iso-in-qemu" ''
          args=(
            -m 2G
            -smp 4
            -cdrom ${self'.packages.iso}/iso/*.iso
            -net none
            -serial stdio
            -drive "if=pflash,format=raw,readonly=on,file=${self'.packages.ovmf}/FV/OVMF_CODE.fd"
            -drive "if=pflash,format=raw,snapshot=on,file=${self'.packages.ovmf_vars}"
          )
          qemu-kvm "''${args[@]}"
        '';
      };
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [ uefi-run sbsigntool python3Packages.ovmfvartool ];
        ovmf = self'.packages.ovmf;
        inherit (self'.packages) ovmf_vars;
      };
    };
  });
}

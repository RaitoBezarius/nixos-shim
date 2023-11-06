{
  inputs = {
    flake-compat = {
      url = "github:lheckemann/flake-compat/add-overrideInputs";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:lheckemann/nixpkgs/shim";
    lanzaboote.url = "github:nix-community/lanzaboote/v0.3.0";
  };
  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (
    toplevel@{ config, self, ... }: {
    systems = ["x86_64-linux" "aarch64-linux"];
    flake.hydraJobs = {
      inherit (self) packages;
    };
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
            -bios ${pkgs.OVMF.fd}/FV/OVMF.fd
            -drive if=virtio,file=${self'.packages.test-image}/test.qcow2,snapshot=on
            -net none
            #-cdrom ~/deploy/result/iso/nixos.iso
          )
          ${pkgs.qemu_kvm}/bin/qemu-kvm "''${args[@]}"
        '';

        # nix build .#iso
        # qemu-kvm -m 2G -smp 4 -bios $ovmf/FV/OVMF.fd -cdrom result/iso/*.iso -net none
        iso = let
          configModule = { modulesPath, ... }: {
            imports = [
              #(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
              (modulesPath + "/installer/cd-dvd/iso-image.nix")
            ];
            secureboot = {
              signingCertificate = ./pki/snakeoil-vendor-cert.pem;
              privateKeyFile = ./pki/snakeoil-vendor-key.pem;
              shim = "${self'.packages.shim-signed}/share/shim/shimx64.efi";
            };
            # for faster build
            isoImage.squashfsCompression = "zstd -Xcompression-level 6";
            isoImage.makeEfiBootable = true;
          };
          nixos = pkgs.nixos configModule;
        in nixos.config.system.build.isoImage;
      };
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [ uefi-run sbsigntool ];
        ovmf = (pkgs.OVMF.override {secureBoot = true;}).fd;
      };
    };
  });
}

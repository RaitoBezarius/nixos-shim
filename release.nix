{ nixpkgs ? null
, systems ? ["x86_64-linux" "aarch64-linux"]
}:
((import ./flake-compat.nix).defaultNix.overrideInputs {
  nixpkgs = nixpkgs;
}).hydraJobs

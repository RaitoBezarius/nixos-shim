{ nixpkgs ? null
, systems ? ["x86_64-linux" "aarch64-linux"]
, flake-compat ? ./flake-compat.nix
}:
((import flake-compat).defaultNix.overrideInputs {
  nixpkgs = nixpkgs;
}).hydraJobs

{ nixpkgs ? null
, systems ? ["x86_64-linux" "aarch64-linux"]
, flake-compat ? ./flake-compat.nix
}@args:
((import flake-compat { src = ./.; }).defaultNix.overrideInputs args).hydraJobs

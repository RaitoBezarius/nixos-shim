terraform {
  required_providers {
    hydra = {
      version = "~> 0.1"
      source  = "DeterminateSystems/hydra"
    }
  }
}

provider "hydra" {
  host = "https://hydra.newtype.fr"
}

resource "hydra_project" "nixos-shim" {
  name         = "nixos-shim"
  display_name = "NixOS signed binaries"
  description  = "NixOS signed binaries with Secure Boot schemes"
  homepage     = "https://github.com/RaitoBezarius/nixos-shim"
  owner        = "raito"
  enabled      = true
  visible      = true
}


resource "hydra_jobset" "main" {
  project     = hydra_project.nixos-shim.name
  state       = "enabled"
  visible     = true
  name        = "main"
  type        = "legacy"
  description = "master branch"

  nix_expression {
    file = "release.nix"
    input = "nixos-shim"
  }

  input {
    name = "nixpkgs"
    type = "git"
    value = "https://github.com/NixOS/nixpkgs nixos-unstable-small"
    notify_committers = false
  }

  input {
    name = "nixos-shim"
    type = "git"
    value = "https://github.com/RaitoBezarius/nixos-shim"
    notify_committers = false
  }

  check_interval    = 0
  scheduling_shares = 3000
  keep_evaluations  = 3

  email_notifications = true
}

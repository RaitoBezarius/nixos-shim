terraform {
  required_providers {
    hydra = {
      version = "~> 0.1"
      source  = "DeterminateSystems/hydra"
    }
  }

  # garage key new --name linus-nixos-shim-terraform-state
  # garage bucket allow --key linus-nixos-shim-terraform-state newtype-terraform-state --read --write
  # Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to enable terraform to access the state

  # TODO: hydra.nixos.org?
  backend "s3" {
    endpoint                    = "https://s3.infra.newtype.fr/"
    bucket                      = "newtype-terraform-state"
    key                         = "terraform.tfstate"
    region                      = "garage"
    skip_region_validation      = true
    skip_metadata_api_check     = true
    skip_credentials_validation = true
    force_path_style            = true
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
  type        = "flake"
  description = "main branch"
  flake_uri   = "github:RaitoBezarius/nixos-shim"

  check_interval    = 300
  scheduling_shares = 3000
  keep_evaluations  = 3

  email_notifications = true
}

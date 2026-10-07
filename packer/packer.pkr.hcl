# ============================================================================================= #
# packer.pkr.hcl — Packer version constraint and plugin declarations                          #
# ============================================================================================= #

packer {

  // Declare required Packer version.
  required_version = "1.15.0"

  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "= 1.8.2"
    }

    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "= 1.1.4"
    }

    git = {
      source  = "github.com/ethanmdavidson/git"
      version = "= 0.6.5"
    }
  }

}

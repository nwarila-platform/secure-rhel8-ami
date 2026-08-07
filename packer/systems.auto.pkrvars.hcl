# ============================================================================================= #
# RHEL 8 — UEFI-preferred source AMI, SSH communicator, ansible-framework os_bootstrap        #
#                                                                                               #
# Consumer configuration for the aws-packer-framework.                                          #
# See: https://github.com/nwarila-platform/aws-packer-framework/blob/main/docs/reference/template-contract.md #
# ============================================================================================= #

# --- Source AMI -------------------------------------------------------------------------- #
# This committed block is the audit trail of which base image each build consumed. Owner
# 309956199498 is Red Hat's commercial AMI account; the owner-scoped filter tracks the
# latest official RHEL 8.10 x86_64 Hourly2 GP3 AMI. Pin ami_id instead of the filter for a
# fully reproducible build.
source_ami = {
  ami_id = null
  owners = ["309956199498"]
  filters = {
    name                = "RHEL-8.10*_HVM-*-x86_64-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
}

# --- User Data Template ------------------------------------------------------------------ #
# Consumer-owned cloud-init template, synced into the framework packer/ working directory by
# the caller workflow. Rendered with the guaranteed template variable contract.
user_data_template = {
  template_path = "./user-data.pkrtpl.hcl"
  extra_vars    = {}
}

# --- Ansible Configuration --------------------------------------------------------------- #
# Consumer-owned Ansible provisioner configuration. The framework handles connection wiring
# (SSH) automatically; this repo owns the playbook, and roles are sourced from:
# https://github.com/nwarila-platform/ansible-framework
ansible_config = {
  playbook_path     = "./rhel-8.yml"
  requirements_path = null
  roles_path        = "../../ansible-framework"
  config_path       = "../../ansible-framework/ansible.cfg"
  extra_vars        = {}
}

# --- Packer Image ------------------------------------------------------------------------ #
packer_image = {

  # Connection Settings
  communicator                 = "ssh"
  ssh_interface                = "public_ip"
  ssh_timeout                  = "15m"
  winrm_timeout                = null
  winrm_port                   = null
  winrm_use_ssl                = null
  winrm_insecure               = null
  winrm_use_ntlm               = null
  winrm_transport              = null
  winrm_server_cert_validation = null

  # Template Metadata
  os_language = "en_US"
  os_keyboard = "us"
  os_timezone = "UTC"
  os_family   = "linux"
  os_name     = "rhel"
  os_version  = "8"

  # General Settings
  region          = "us-east-1"
  ami_name        = "secure-rhel8"
  ami_description = "Secure RHEL 8 AMI built with Packer (STIG/CIS hardening track)"
  ami_regions     = []
  ami_users       = []
  ami_org_arns    = []
  tags = {
    Name       = "secure-rhel8"
    OSFamily   = "linux"
    OSName     = "rhel"
    OSVersion  = "8"
    Hardening  = "stig-cis"
    ManagedBy  = "aws-packer-framework"
    Repository = "nwarila-platform/secure-rhel8-ami"
  }
  run_tags = {
    Name      = "packer-build-secure-rhel8"
    ManagedBy = "aws-packer-framework"
  }
  snapshot_tags = {
    Name      = "secure-rhel8"
    ManagedBy = "aws-packer-framework"
  }

  # Build Instance
  instance_type        = "t3.medium"
  iam_instance_profile = null
  ebs_optimized        = true

  # AMI Settings
  ena_support           = true
  sriov_support         = false
  imds_support          = "v2.0"
  encrypt_boot          = true
  kms_key_id            = null
  force_deregister      = false
  force_delete_snapshot = false

}

launch_block_device_mappings = [
  {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    kms_key_id            = null
    delete_on_termination = true
  }
]

ami_block_device_mappings = []

# NOTE: temporary_security_group_source_cidrs = ["0.0.0.0/0"] is a bootstrap EXCEPTION for
# default-VPC builds. Scope this to the CI egress CIDR, or switch
# ssh_interface = "session_manager" with an instance profile and no inbound rules at all.
vpc_config = {
  vpc_id                                = null
  subnet_id                             = null
  security_group_ids                    = null
  associate_public_ip_address           = true
  temporary_security_group_source_cidrs = ["0.0.0.0/0"]
}

metadata_options = {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
  instance_metadata_tags      = "disabled"
}

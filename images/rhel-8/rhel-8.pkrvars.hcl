# ============================================================================================= #
# RHEL 8 — UEFI-preferred source AMI, SSH communicator, ansible-framework os_bootstrap        #
#                                                                                               #
# This image's inputs to the Packer template under packer/ (variables in packer/variables.pkr.hcl). #
# ============================================================================================= #

# --- Source AMI -------------------------------------------------------------------------- #
# This committed block is the audit trail of the source selection rule; the AMI ID each build
# resolved is in that build's log ("Found Image ID"). Owner 309956199498 is Red Hat's
# commercial AMI account; the owner-scoped filter tracks the latest official RHEL 8.10 x86_64
# Hourly2 GP3 AMI. Pin ami_id instead of the filter to make the source AMI selection reproducible.
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
# This image's cloud-init template, beside this file; the path is relative to packer/, the
# directory Packer runs from. Rendered with the guaranteed template variable contract.
user_data_template = {
  template_path = "../images/rhel-8/user-data.pkrtpl.hcl"
  extra_vars    = {}
}

# --- Ansible Configuration --------------------------------------------------------------- #
# This image's Ansible provisioner configuration. The template handles connection wiring
# (SSH) automatically; the playbook lives beside this file, and roles are sourced from the
# ansible-framework checkout the workflow places at the repository root:
# https://github.com/nwarila-platform/ansible-framework
ansible_config = {
  playbook_path     = "../images/rhel-8/playbook.yml"
  requirements_path = null
  roles_path        = "../ansible-framework"
  config_path       = "../ansible-framework/ansible.cfg"
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
    Name         = "secure-rhel8"
    ImageFamily  = "rhel"
    Hardening    = "stig-cis"
    ManagedBy    = "aws-packer-framework"
    Repository   = "nwarila-platform/secure-rhel8-ami"
    RepositoryId = "1326894519"
  }
  # The RepositoryId tag is the IAM identity boundary: ten statements of the build and
  # publish policies test ec2:ResourceTag/RepositoryId (terminate, security-group lifecycle,
  # image deregistration and snapshot deletion among them; see docs/reference/aws-iam/).
  run_tags = {
    Name         = "packer-build-secure-rhel8"
    ManagedBy    = "aws-packer-framework"
    Repository   = "nwarila-platform/secure-rhel8-ami"
    RepositoryId = "1326894519"
  }
  snapshot_tags = {
    Name         = "secure-rhel8"
    ManagedBy    = "aws-packer-framework"
    Repository   = "nwarila-platform/secure-rhel8-ami"
    RepositoryId = "1326894519"
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

# --- Surrogate Volume -------------------------------------------------------------------- #
# Blank volume the STIG-partitioned image is assembled onto (see the second play in
# playbook.yml). The template's amazon-ebssurrogate source attaches it at device_name and
# registers the AMI from it as ami_root_device_name. Builds select this path explicitly:
# packer build -only=amazon-ebssurrogate.packer_image
surrogate = {
  device_name          = "/dev/xvdf"
  ami_root_device_name = "/dev/sda1"
  # UEFI/GPT layout with an EFI system partition and shim+grub2-efi (see playbook.yml play 2).
  # The template hard-blocks anything but "uefi".
  boot_mode   = "uefi"
  volume_size = 30
  volume_type = "gp3"
  iops        = 3000
  throughput  = 125
  encrypted   = true
  kms_key_id  = null
}

# Placement is pinned deliberately: an explicit VPC makes the IAM authorization context carry
# a concrete VPC ARN, letting the build policy pin CreateSecurityGroup to exactly this VPC
# (a null vpc_id evaluates as vpc/* and forces a wildcard grant).
# NOTE: temporary_security_group_source_cidrs = ["0.0.0.0/0"] is a bootstrap EXCEPTION.
# Scope this to the CI egress CIDR, or switch ssh_interface = "session_manager" with an
# instance profile and no inbound rules at all.
vpc_config = {
  vpc_id                                = "vpc-024afb5e25a56792c"
  subnet_id                             = "subnet-01a8835a525008dfc"
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

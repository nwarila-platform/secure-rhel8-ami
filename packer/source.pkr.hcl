# ============================================================================================= #
# source.pkr.hcl — Amazon EBS source definition                                               #
# ============================================================================================= #

source "amazon-ebs" "packer_image" {

  # AWS Configuration
  # Credentials come from the ambient AWS credential chain (environment variables, OIDC/web
  # identity, instance profile) or the optional shared-credentials profile. Static access keys
  # are deliberately not part of the framework variable contract.
  region  = local.packer_image.region
  profile = var.aws_profile

  dynamic "assume_role" {
    for_each = var.aws_assume_role == null ? [] : [1]

    content {
      role_arn     = var.aws_assume_role["role_arn"]
      session_name = var.aws_assume_role["session_name"]
      external_id  = var.aws_assume_role["external_id"]
    }
  }

  # Communicator Configuration
  communicator = local.packer_image.communicator

  # SSH Configuration (used when communicator = "ssh")
  # Linux/SSH builds authenticate exclusively via a Packer-generated temporary EC2 keypair.
  # There is no SSH password path; privilege escalation relies on the source AMI's
  # passwordless sudo grant for the cloud-init default user.
  ssh_interface = local.packer_image.communicator == "ssh" ? local.packer_image.ssh_interface : null
  ssh_port      = local.packer_image.communicator == "ssh" ? 22 : null
  ssh_timeout   = local.packer_image.communicator == "ssh" ? local.packer_image.ssh_timeout : null
  ssh_username  = local.packer_image.communicator == "ssh" ? var.deploy_user_name : null

  # WinRM Configuration (used when communicator = "winrm")
  winrm_username = local.packer_image.communicator == "winrm" ? var.deploy_user_name : null
  winrm_password = local.packer_image.communicator == "winrm" ? var.deploy_user_password : null
  winrm_port     = local.packer_image.communicator == "winrm" ? local.packer_image.winrm_port : null
  winrm_timeout  = local.packer_image.communicator == "winrm" ? local.packer_image.winrm_timeout : null
  winrm_insecure = local.packer_image.communicator == "winrm" ? local.packer_image.winrm_insecure : null
  winrm_use_ntlm = local.packer_image.communicator == "winrm" ? local.packer_image.winrm_use_ntlm : null
  winrm_use_ssl  = local.packer_image.communicator == "winrm" ? local.packer_image.winrm_use_ssl : null

  # General Settings
  ami_name        = local.packer_image.ami_name
  ami_description = local.packer_image.ami_description
  ami_regions     = local.packer_image.ami_regions
  ami_users       = local.packer_image.ami_users
  ami_org_arns    = local.packer_image.ami_org_arns
  tags            = local.packer_image.tags
  run_tags        = local.packer_image.run_tags
  snapshot_tags   = local.packer_image.snapshot_tags

  # Build Instance
  instance_type        = local.packer_image.instance_type
  iam_instance_profile = local.packer_image.iam_instance_profile
  ebs_optimized        = local.packer_image.ebs_optimized
  user_data            = local.user_data

  # AMI Settings
  # Boot mode and NitroTPM support are inherited from the source AMI by the amazon-ebs
  # builder (CreateImage flow) and cannot be overridden here.
  ena_support           = local.packer_image.ena_support
  sriov_support         = local.packer_image.sriov_support
  imds_support          = local.packer_image.imds_support
  encrypt_boot          = local.packer_image.encrypt_boot
  kms_key_id            = local.packer_image.kms_key_id
  force_deregister      = local.packer_image.force_deregister
  force_delete_snapshot = local.packer_image.force_delete_snapshot

  # Source AMI
  # Either a pinned ami_id or an owner-scoped filter; the variable contract rejects
  # unscoped filters at validate time (see variables.pkr.hcl).
  source_ami = local.source_ami.ami_id

  dynamic "source_ami_filter" {
    for_each = local.source_ami.ami_id == null ? [1] : []

    content {
      filters     = local.source_ami.filters
      owners      = local.source_ami.owners
      most_recent = local.source_ami.most_recent
    }
  }

  # Network Placement
  vpc_id                                = local.vpc_config.vpc_id
  subnet_id                             = local.vpc_config.subnet_id
  security_group_ids                    = local.vpc_config.security_group_ids
  associate_public_ip_address           = local.vpc_config.associate_public_ip_address
  temporary_security_group_source_cidrs = local.vpc_config.temporary_security_group_source_cidrs

  # Instance Metadata Service (IMDSv2 enforced by normalized defaults)
  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = local.metadata_options.instance_metadata_tags
  }


  dynamic "launch_block_device_mappings" {
    for_each = local.launch_block_device_mappings
    iterator = mapping

    content {
      device_name           = mapping.value["device_name"]
      volume_size           = mapping.value["volume_size"]
      volume_type           = mapping.value["volume_type"]
      iops                  = mapping.value["iops"]
      throughput            = mapping.value["throughput"]
      encrypted             = mapping.value["encrypted"]
      kms_key_id            = mapping.value["kms_key_id"]
      delete_on_termination = mapping.value["delete_on_termination"]
    }
  }


  dynamic "ami_block_device_mappings" {
    for_each = coalesce(local.ami_block_device_mappings, [])
    iterator = mapping

    content {
      device_name           = mapping.value["device_name"]
      volume_size           = mapping.value["volume_size"]
      volume_type           = mapping.value["volume_type"]
      iops                  = mapping.value["iops"]
      throughput            = mapping.value["throughput"]
      encrypted             = mapping.value["encrypted"]
      kms_key_id            = mapping.value["kms_key_id"]
      delete_on_termination = mapping.value["delete_on_termination"]
    }
  }

}

# Surrogate-volume variant of the same contract. The build instance boots from the source AMI,
# a blank volume (var.surrogate) is attached alongside it, consumer provisioning partitions
# that volume and copies the configured OS in, and the AMI is registered from the surrogate —
# the path for partition layouts the source AMI cannot provide (e.g. STIG-mandated separate
# filesystems). Select it with packer build -only=amazon-ebssurrogate.packer_image; an unfiltered build builds both sources.
source "amazon-ebssurrogate" "packer_image" {

  # AWS Configuration
  region  = local.packer_image.region
  profile = var.aws_profile

  dynamic "assume_role" {
    for_each = var.aws_assume_role == null ? [] : [1]

    content {
      role_arn     = var.aws_assume_role["role_arn"]
      session_name = var.aws_assume_role["session_name"]
      external_id  = var.aws_assume_role["external_id"]
    }
  }

  # Communicator Configuration (SSH only; surrogate imaging requires a Linux build instance)
  communicator  = "ssh"
  ssh_interface = local.packer_image.ssh_interface
  ssh_port      = 22
  ssh_timeout   = local.packer_image.ssh_timeout
  ssh_username  = var.deploy_user_name

  # General Settings
  ami_name        = local.packer_image.ami_name
  ami_description = local.packer_image.ami_description
  ami_regions     = local.packer_image.ami_regions
  ami_users       = local.packer_image.ami_users
  ami_org_arns    = local.packer_image.ami_org_arns
  tags            = local.packer_image.tags
  run_tags        = local.packer_image.run_tags
  snapshot_tags   = local.packer_image.snapshot_tags

  # Build Instance
  instance_type        = local.packer_image.instance_type
  iam_instance_profile = local.packer_image.iam_instance_profile
  ebs_optimized        = local.packer_image.ebs_optimized
  user_data            = local.user_data

  # AMI Settings (RegisterImage flow)
  # boot_mode is UEFI-only (hard-blocked to "uefi" by the variable contract): consumer
  # provisioning must build a GPT layout with an EFI system partition and a UEFI GRUB, and the
  # registered AMI boots UEFI-only — matching the UEFI posture of the org's other frameworks.
  ami_virtualization_type = "hvm"
  boot_mode               = local.surrogate.boot_mode
  ena_support             = local.packer_image.ena_support
  sriov_support           = local.packer_image.sriov_support
  imds_support            = local.packer_image.imds_support
  force_deregister        = local.packer_image.force_deregister
  force_delete_snapshot   = local.packer_image.force_delete_snapshot

  # Source AMI
  source_ami = local.source_ami.ami_id

  dynamic "source_ami_filter" {
    for_each = local.source_ami.ami_id == null ? [1] : []

    content {
      filters     = local.source_ami.filters
      owners      = local.source_ami.owners
      most_recent = local.source_ami.most_recent
    }
  }

  # Network Placement
  vpc_id                                = local.vpc_config.vpc_id
  subnet_id                             = local.vpc_config.subnet_id
  security_group_ids                    = local.vpc_config.security_group_ids
  associate_public_ip_address           = local.vpc_config.associate_public_ip_address
  temporary_security_group_source_cidrs = local.vpc_config.temporary_security_group_source_cidrs

  # Instance Metadata Service (IMDSv2 enforced by normalized defaults)
  metadata_options {
    http_endpoint               = local.metadata_options.http_endpoint
    http_tokens                 = local.metadata_options.http_tokens
    http_put_response_hop_limit = local.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = local.metadata_options.instance_metadata_tags
  }

  # Launch devices: the consumer's mappings (first entry overrides the source-AMI root on the
  # build instance) plus the blank surrogate volume the image is assembled onto.
  dynamic "launch_block_device_mappings" {
    for_each = concat(
      local.launch_block_device_mappings,
      [
        {
          device_name           = local.surrogate.device_name
          volume_size           = local.surrogate.volume_size
          volume_type           = local.surrogate.volume_type
          iops                  = local.surrogate.iops
          throughput            = local.surrogate.throughput
          encrypted             = local.surrogate.encrypted
          kms_key_id            = local.surrogate.kms_key_id
          delete_on_termination = true
        }
      ]
    )
    iterator = mapping

    content {
      device_name           = mapping.value["device_name"]
      volume_size           = mapping.value["volume_size"]
      volume_type           = mapping.value["volume_type"]
      iops                  = mapping.value["iops"]
      throughput            = mapping.value["throughput"]
      encrypted             = mapping.value["encrypted"]
      kms_key_id            = mapping.value["kms_key_id"]
      delete_on_termination = mapping.value["delete_on_termination"]
    }
  }

  # The registered AMI's root device maps to the surrogate volume's snapshot.
  ami_root_device {
    source_device_name    = local.surrogate.device_name
    device_name           = local.surrogate.ami_root_device_name
    volume_size           = local.surrogate.volume_size
    volume_type           = local.surrogate.volume_type
    delete_on_termination = true
  }

}

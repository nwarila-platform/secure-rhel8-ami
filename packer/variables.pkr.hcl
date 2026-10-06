# ============================================================================================ #
# variables.pkr.hcl — Input variable declarations for the AWS Packer Framework                 #
# ============================================================================================ #

#region ------ [ AWS Settings ] --------------------------------------------------------------- #

variable "aws_region" {
  type        = string
  description = "Required top-level region; it overrides packer_image.region. CI injects it through PKR_VAR_aws_region."
}

variable "aws_profile" {
  type        = string
  default     = null
  description = "Optional shared-credentials profile name. When null, the standard AWS credential chain is used (environment variables, OIDC/web identity, instance profile). The framework never accepts static access keys as Packer variables."
}

variable "aws_assume_role" {
  description = "Optional IAM role to assume for the build. When null, the ambient credential identity is used directly. Prefer short-lived role assumption (e.g. GitHub OIDC into a scoped build role) over long-lived credentials."
  default     = null
  type = object({
    role_arn     = string
    session_name = string
    external_id  = string
  })
}

#endregion --- [ AWS Settings ] --------------------------------------------------------------- #

#region ------ [ Deploy User ] ---------------------------------------------------------------- #

variable "deploy_user_name" {
  type        = string
  description = "The username the communicator connects as inside the guest operating system. For Linux/SSH builds this is the source AMI's cloud-init default user (e.g. ec2-user for RHEL); SSH key material is a Packer-generated temporary keypair, and privilege escalation uses the AMI's passwordless sudo grant. For Windows/WinRM builds this is the WinRM user provisioned by the consumer's user-data bootstrap."
  sensitive   = true
}

variable "deploy_user_password" {
  type        = string
  default     = null
  description = "WinRM password for Windows/WinRM builds, provisioned by the consumer's user-data bootstrap. Used at build time only and never baked into the resulting AMI. Ignored for Linux/SSH builds, which authenticate exclusively with the Packer-generated temporary keypair."
  sensitive   = true
}

#endregion --- [ Deploy User ] ---------------------------------------------------------------- #

#region ------ [ User Data Template ] --------------------------------------------------------- #

variable "user_data_template" {
  description = "Optional consumer-provided user-data template configuration. The framework renders this template with the guaranteed template variable contract and passes the result as EC2 user data to the build instance (cloud-init for Linux, EC2Launch/Autounattend bootstrap for Windows). When null, no user data is sent and the source AMI's stock first-boot behavior is used."
  default     = null
  type = object({
    template_path = string
    extra_vars    = map(string)
  })
}

#endregion --- [ User Data Template ] --------------------------------------------------------- #

#region ------ [ Ansible Configuration ] ------------------------------------------------------ #

variable "ansible_config" {
  description = "Consumer-provided Ansible provisioner configuration. The framework handles connection wiring (SSH/WinRM) automatically based on communicator type; consumer owns playbook content and roles."
  type = object({
    playbook_path     = string
    requirements_path = string
    roles_path        = string
    config_path       = string
    extra_vars        = map(string)
  })
}

variable "ansible_extra_vars_file" {
  description = "Optional Ansible variables file selected by the workflow matrix, passed as --extra-vars @file. Null passes nothing."
  type        = string
  default     = null
}

#endregion --- [ Ansible Configuration ] ------------------------------------------------------ #

#region ------ [ Packer Image ] --------------------------------------------------------------- #

variable "packer_image" {
  description = "The primary configuration object for the AMI build. Defines OS metadata, connection settings, AMI naming/distribution, build-instance hardware, and AMI hardening posture (encryption, IMDSv2). Boot mode and NitroTPM support are inherited from the source AMI by the amazon-ebs builder and are therefore not part of this contract."
  type = object({

    # Connection Settings
    communicator                 = string
    ssh_interface                = string
    ssh_timeout                  = string
    winrm_timeout                = string
    winrm_port                   = number
    winrm_use_ssl                = bool
    winrm_insecure               = bool
    winrm_use_ntlm               = bool
    winrm_transport              = string
    winrm_server_cert_validation = string

    # Template Metadata
    os_language = string
    os_keyboard = string
    os_timezone = string
    os_family   = string
    os_name     = string
    os_version  = string

    # General Settings
    region          = string
    ami_name        = string
    ami_description = string
    ami_regions     = list(string)
    ami_users       = list(string)
    ami_org_arns    = list(string)
    tags            = map(string)
    run_tags        = map(string)
    snapshot_tags   = map(string)

    # Build Instance
    instance_type        = string
    iam_instance_profile = string
    ebs_optimized        = bool

    # AMI Settings
    ena_support           = bool
    sriov_support         = bool
    imds_support          = string
    encrypt_boot          = bool
    kms_key_id            = string
    force_deregister      = bool
    force_delete_snapshot = bool

  })

  validation {
    condition     = var.packer_image.communicator == null || contains(["ssh", "winrm"], var.packer_image.communicator)
    error_message = "The packer_image.communicator value must be \"ssh\" or \"winrm\"."
  }

  validation {
    condition     = var.packer_image.ssh_interface == null || contains(["public_ip", "private_ip", "public_dns", "private_dns", "session_manager"], var.packer_image.ssh_interface)
    error_message = "The packer_image.ssh_interface value must be one of \"public_ip\", \"private_ip\", \"public_dns\", \"private_dns\", or \"session_manager\"."
  }

  validation {
    condition     = var.packer_image.imds_support == null || var.packer_image.imds_support == "v2.0"
    error_message = "The packer_image.imds_support value must be \"v2.0\" (IMDSv2 required) or null to accept the framework's IMDSv2-enforced default."
  }

}

variable "source_ami" {
  description = "The source AMI configuration for the build. Consumers must supply this value — either a pinned ami_id or an owner-scoped filter — set in the image's pkrvars file under images/<image>/ and passed with -var-file. Its history records the selection rule; the AMI ID each build resolved is in that build's log."
  default     = null
  type = object({
    ami_id      = string
    owners      = list(string)
    filters     = map(string)
    most_recent = bool
  })

  validation {
    condition     = var.source_ami != null
    error_message = "The source_ami value must be supplied explicitly by the caller. Pin an ami_id or an owner-scoped filter in the image's pkrvars file under images/<image>/."
  }

  validation {
    condition = var.source_ami == null || var.source_ami.ami_id != null || (
      var.source_ami.filters != null && var.source_ami.owners != null && length(coalesce(var.source_ami.owners, [])) > 0
    )
    error_message = "The source_ami value must set ami_id, or set filters together with a non-empty owners list. Unscoped AMI filters are rejected to prevent resolving a look-alike AMI from an untrusted account."
  }
}

variable "surrogate" {
  description = "Surrogate-volume configuration for the amazon-ebssurrogate source, used when the image needs a partition layout the source AMI cannot provide (e.g. STIG-mandated separate filesystems). The blank volume is attached to the build instance at device_name; consumer provisioning partitions it and copies the configured OS in; the AMI is registered from that volume as ami_root_device_name. When null, the ebssurrogate source still validates with defaults; an unfiltered build builds it too, so builds select their source with -only."
  default     = null
  type = object({
    device_name          = string
    ami_root_device_name = string
    boot_mode            = string
    volume_size          = number
    volume_type          = string
    iops                 = number
    throughput           = number
    encrypted            = bool
    kms_key_id           = string
  })

  validation {
    condition     = try(var.surrogate.boot_mode, null) == null || try(var.surrogate.boot_mode, "") == "uefi"
    error_message = "The surrogate.boot_mode value must be \"uefi\". Legacy BIOS and uefi-preferred (which permits a BIOS fallback) are hard-blocked: this framework registers UEFI-only images, matching the UEFI posture of the org's other Packer frameworks. Consumer provisioning must build a GPT layout with an EFI system partition and a UEFI GRUB, and the registered AMI boots UEFI-only."
  }
}

variable "launch_block_device_mappings" {
  description = "List of block device mappings for the build instance. At least one mapping is required; the first mapping is treated as the root volume for the template variable contract."
  type = list(
    object({
      device_name           = string
      volume_size           = number
      volume_type           = string
      iops                  = number
      throughput            = number
      encrypted             = bool
      kms_key_id            = string
      delete_on_termination = bool
    })
  )

  validation {
    condition     = length(var.launch_block_device_mappings) > 0
    error_message = "At least one launch block device mapping must be defined. The first mapping is treated as the root volume."
  }
}

variable "ami_block_device_mappings" {
  description = "Additional block device mappings attached to the registered AMI beyond those on the build instance (e.g. pre-declared data volumes)."
  default     = []
  type = list(
    object({
      device_name           = string
      volume_size           = number
      volume_type           = string
      iops                  = number
      throughput            = number
      encrypted             = bool
      kms_key_id            = string
      delete_on_termination = bool
    })
  )
}

variable "vpc_config" {
  description = "Network placement for the build instance. Fields may be null to fall back to the account's default VPC behavior, but the object itself is required so network placement is always a conscious consumer decision."
  type = object({
    vpc_id                                = string
    subnet_id                             = string
    security_group_ids                    = list(string)
    associate_public_ip_address           = bool
    temporary_security_group_source_cidrs = list(string)
  })
}

variable "metadata_options" {
  description = "Instance metadata service configuration for the build instance. Normalized defaults enforce IMDSv2 (http_tokens = required)."
  default     = null
  type = object({
    http_endpoint               = string
    http_tokens                 = string
    http_put_response_hop_limit = number
    instance_metadata_tags      = string
  })
}

#endregion --- [ Packer Image ] --------------------------------------------------------------- #

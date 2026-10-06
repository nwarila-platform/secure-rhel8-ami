# ============================================================================================ #
# locals.pkr.hcl — Variable normalization and template rendering                               #
#                                                                                              #
# This file is the "brains" of the framework. It normalizes consumer inputs with sensible      #
# defaults, assembles the template variable contract, and renders the optional consumer        #
# user-data template for the build instance.                                                   #
# ============================================================================================ #

locals {

  #region ------ [ Packer Image Normalization ] ---------------------------------------------- #

  packer_image = {

    # Connection Settings
    communicator  = coalesce(var.packer_image.communicator, "ssh")
    ssh_interface = coalesce(var.packer_image.ssh_interface, "public_ip")
    ssh_timeout   = coalesce(var.packer_image.ssh_timeout, "15m")
    winrm_timeout = coalesce(var.packer_image.winrm_timeout, "60m")
    winrm_use_ssl = coalesce(var.packer_image.winrm_use_ssl, true)
    winrm_port = coalesce(
      var.packer_image.winrm_port,
      coalesce(var.packer_image.winrm_use_ssl, true) ? 5986 : 5985
    )
    winrm_insecure = coalesce(
      var.packer_image.winrm_insecure,
      coalesce(var.packer_image.winrm_use_ssl, true) ? false : true
    )
    winrm_use_ntlm = coalesce(var.packer_image.winrm_use_ntlm, true)
    winrm_transport = coalesce(
      var.packer_image.winrm_transport,
      coalesce(var.packer_image.winrm_use_ntlm, true) ? "ntlm" : "basic"
    )
    winrm_server_cert_validation = coalesce(
      var.packer_image.winrm_server_cert_validation,
      coalesce(var.packer_image.winrm_use_ssl, true) ? "validate" : "ignore"
    )

    # Template Metadata
    os_language = coalesce(var.packer_image.os_language, "en_US")
    os_keyboard = coalesce(var.packer_image.os_keyboard, "us")
    os_timezone = coalesce(var.packer_image.os_timezone, "UTC")
    os_family   = var.packer_image.os_family
    os_name     = var.packer_image.os_name
    os_version  = var.packer_image.os_version

    # General Settings
    region          = coalesce(var.aws_region, var.packer_image.region)
    ami_name        = "${var.packer_image.ami_name}-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
    ami_description = "${var.packer_image.ami_description} | Built: ${timestamp()}"
    ami_regions     = coalesce(var.packer_image.ami_regions, [])
    ami_users       = coalesce(var.packer_image.ami_users, [])
    ami_org_arns    = coalesce(var.packer_image.ami_org_arns, [])
    tags            = coalesce(var.packer_image.tags, {})
    run_tags        = coalesce(var.packer_image.run_tags, {})
    snapshot_tags   = coalesce(var.packer_image.snapshot_tags, {})

    # Build Instance
    instance_type        = coalesce(var.packer_image.instance_type, "t3.medium")
    iam_instance_profile = var.packer_image.iam_instance_profile
    ebs_optimized        = coalesce(var.packer_image.ebs_optimized, true)

    # AMI Settings
    ena_support           = var.packer_image.ena_support
    sriov_support         = coalesce(var.packer_image.sriov_support, false)
    imds_support          = coalesce(var.packer_image.imds_support, "v2.0")
    encrypt_boot          = coalesce(var.packer_image.encrypt_boot, true)
    kms_key_id            = var.packer_image.kms_key_id
    force_deregister      = coalesce(var.packer_image.force_deregister, false)
    force_delete_snapshot = coalesce(var.packer_image.force_delete_snapshot, false)

  }

  #endregion --- [ Packer Image Normalization ] ---------------------------------------------- #

  #region ------ [ Template Variable Contract ] ---------------------------------------------- #

  template_vars = {

    # Credentials
    # SSH key material is a Packer-generated temporary keypair injected through EC2 keypair
    # plumbing; no password or key variables flow through the template contract.
    deploy_user_name = var.deploy_user_name

    # Locale
    os_language = local.packer_image.os_language
    os_keyboard = local.packer_image.os_keyboard
    os_timezone = local.packer_image.os_timezone

    # OS Metadata
    os_family  = local.packer_image.os_family
    os_name    = local.packer_image.os_name
    os_version = local.packer_image.os_version

    # Build Context
    build_region       = local.packer_image.region
    build_communicator = local.packer_image.communicator

    # Hardware Summary
    hw_instance_type    = local.packer_image.instance_type
    hw_root_device_name = var.launch_block_device_mappings[0].device_name
    hw_root_volume_size = var.launch_block_device_mappings[0].volume_size

  }

  #endregion --- [ Template Variable Contract ] ---------------------------------------------- #

  #region ------ [ User Data ] --------------------------------------------------------------- #

  user_data = var.user_data_template == null ? null : templatefile(
    var.user_data_template.template_path,
    merge(
      local.template_vars,
      coalesce(var.user_data_template.extra_vars, {})
    )
  )

  #endregion --- [ User Data ] --------------------------------------------------------------- #

  #region ------ [ Hardware Normalization ] -------------------------------------------------- #

  # Normalized even when var.surrogate is null so the ebssurrogate source always validates;
  # an unfiltered build builds it too, so builds select their source with -only.
  surrogate = {
    device_name          = coalesce(var.surrogate == null ? null : var.surrogate.device_name, "/dev/xvdf")
    ami_root_device_name = coalesce(var.surrogate == null ? null : var.surrogate.ami_root_device_name, "/dev/sda1")
    boot_mode            = coalesce(var.surrogate == null ? null : var.surrogate.boot_mode, "uefi")
    volume_size = coalesce(
      var.surrogate == null ? null : var.surrogate.volume_size,
      var.launch_block_device_mappings[0].volume_size
    )
    volume_type = coalesce(var.surrogate == null ? null : var.surrogate.volume_type, "gp3")
    iops        = var.surrogate == null ? null : var.surrogate.iops
    throughput  = var.surrogate == null ? null : var.surrogate.throughput
    encrypted   = coalesce(var.surrogate == null ? null : var.surrogate.encrypted, true)
    kms_key_id  = var.surrogate == null ? null : var.surrogate.kms_key_id
  }

  source_ami = {
    ami_id      = var.source_ami.ami_id
    owners      = var.source_ami.owners
    filters     = var.source_ami.filters
    most_recent = coalesce(var.source_ami.most_recent, true)
  }

  launch_block_device_mappings = [
    for mapping in var.launch_block_device_mappings : {
      device_name           = mapping.device_name
      volume_size           = mapping.volume_size
      volume_type           = coalesce(mapping.volume_type, "gp3")
      iops                  = mapping.iops
      throughput            = mapping.throughput
      encrypted             = coalesce(mapping.encrypted, true)
      kms_key_id            = mapping.kms_key_id
      delete_on_termination = coalesce(mapping.delete_on_termination, true)
    }
  ]

  ami_block_device_mappings = [
    for mapping in var.ami_block_device_mappings : {
      device_name           = mapping.device_name
      volume_size           = mapping.volume_size
      volume_type           = coalesce(mapping.volume_type, "gp3")
      iops                  = mapping.iops
      throughput            = mapping.throughput
      encrypted             = coalesce(mapping.encrypted, true)
      kms_key_id            = mapping.kms_key_id
      delete_on_termination = coalesce(mapping.delete_on_termination, true)
    }
  ]

  vpc_config = {
    vpc_id                                = var.vpc_config.vpc_id
    subnet_id                             = var.vpc_config.subnet_id
    security_group_ids                    = var.vpc_config.security_group_ids
    associate_public_ip_address           = var.vpc_config.associate_public_ip_address
    temporary_security_group_source_cidrs = var.vpc_config.temporary_security_group_source_cidrs
  }

  metadata_options = var.metadata_options == null ? {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
    } : {
    http_endpoint               = coalesce(var.metadata_options.http_endpoint, "enabled")
    http_tokens                 = coalesce(var.metadata_options.http_tokens, "required")
    http_put_response_hop_limit = coalesce(var.metadata_options.http_put_response_hop_limit, 1)
    instance_metadata_tags      = coalesce(var.metadata_options.instance_metadata_tags, "disabled")
  }

  #endregion --- [ Hardware Normalization ] -------------------------------------------------- #

}

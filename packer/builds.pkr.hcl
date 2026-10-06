# ============================================================================================= #
# builds.pkr.hcl - Build definition with consumer-provided Ansible provisioner                  #
# ============================================================================================= #

build {

  # Both sources share the full variable contract and both are in this build; an unfiltered
  # build builds both. Select one with -only (the image workflow passes
  # -only=amazon-ebssurrogate.packer_image; see source.pkr.hcl).
  sources = [
    "source.amazon-ebs.packer_image",
    "source.amazon-ebssurrogate.packer_image",
  ]

  # Ansible Provisioner (SSH communicator - Linux)
  # SSH authentication is handled by the Packer-generated temporary EC2 keypair; no SSH
  # password is wired through Ansible. Privilege escalation relies on the source AMI's
  # passwordless sudo grant for the cloud-init default user, so no become_pass is provided.
  # use_proxy is disabled so Ansible connects straight to the build instance with the
  # Packer key and the real sshd SFTP subsystem — the proxy adapter's hard-coded
  # /usr/lib/sftp-server path breaks module transfer on RHEL-family targets.
  # Builds are expected to provide a real playbook path and an ansible-playbook executable
  # on PATH.
  provisioner "ansible" {
    except                 = (local.packer_image.communicator == "ssh" && var.ansible_config.playbook_path != null) ? [] : ["amazon-ebs.packer_image", "amazon-ebssurrogate.packer_image"]
    use_proxy              = false
    user                   = var.deploy_user_name
    galaxy_file            = var.ansible_config.requirements_path
    galaxy_force_with_deps = var.ansible_config.requirements_path != null ? true : null
    playbook_file          = var.ansible_config.playbook_path
    roles_path             = var.ansible_config.roles_path
    ansible_env_vars = var.ansible_config.config_path != null ? [
      "ANSIBLE_CONFIG=${var.ansible_config.config_path}"
    ] : []
    extra_arguments = concat(
      [
        "--extra-vars", "ansible_user=${var.deploy_user_name}"
      ],
      var.ansible_extra_vars_file == null ? [] : ["--extra-vars", "@${var.ansible_extra_vars_file}"],
      flatten([for k, v in var.ansible_config.extra_vars : ["--extra-vars", "${k}=${v}"]])
    )
  }

  # Ansible Provisioner (WinRM communicator - Windows)
  # Builds are expected to provide a real playbook path and an ansible-playbook
  # executable on PATH.
  # The surrogate source is SSH-only, so it is always excluded from the WinRM provisioner.
  provisioner "ansible" {
    except                 = (local.packer_image.communicator == "winrm" && var.ansible_config.playbook_path != null) ? ["amazon-ebssurrogate.packer_image"] : ["amazon-ebs.packer_image", "amazon-ebssurrogate.packer_image"]
    user                   = var.deploy_user_name
    use_proxy              = false
    galaxy_file            = var.ansible_config.requirements_path
    galaxy_force_with_deps = var.ansible_config.requirements_path != null ? true : null
    playbook_file          = var.ansible_config.playbook_path
    roles_path             = var.ansible_config.roles_path
    ansible_env_vars = var.ansible_config.config_path != null ? [
      "ANSIBLE_CONFIG=${var.ansible_config.config_path}"
    ] : []
    extra_arguments = concat(
      [
        "--extra-vars", "ansible_user=${var.deploy_user_name}",
        "--extra-vars", "ansible_password=${var.deploy_user_password}",
        "--extra-vars", "ansible_connection=winrm",
        "--extra-vars", "ansible_port=${local.packer_image.winrm_port}",
        "--extra-vars", "ansible_winrm_scheme=${local.packer_image.winrm_use_ssl ? "https" : "http"}",
        "--extra-vars", "ansible_winrm_transport=${local.packer_image.winrm_transport}",
        "--extra-vars", "ansible_winrm_server_cert_validation=${local.packer_image.winrm_server_cert_validation}"
      ],
      var.ansible_extra_vars_file == null ? [] : ["--extra-vars", "@${var.ansible_extra_vars_file}"],
      flatten([for k, v in var.ansible_config.extra_vars : ["--extra-vars", "${k}=${v}"]])
    )
  }

  post-processor "manifest" {
    output = join("", [
      path.root, "/manifests/",
      formatdate("YYYY-MM-DD_HH-mm-ss", timestamp()), ".json"
    ])
    strip_path = true
    strip_time = true
    custom_data = {
      build_username = var.deploy_user_name
      build_date     = timestamp()
      build_version  = data.git-repository.cwd.head
      region         = local.packer_image.region
      instance_type  = local.packer_image.instance_type
      imds_support   = local.packer_image.imds_support
      encrypt_boot   = local.packer_image.encrypt_boot
      os_name        = local.packer_image.os_name
      os_version     = local.packer_image.os_version
    }
  }
}

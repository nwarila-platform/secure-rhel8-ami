#cloud-config
# ============================================================================================= #
# user-data.pkrtpl.hcl — cloud-init user data for the secure-rhel8 build instance             #
#                                                                                               #
# Rendered by aws-packer-framework with the guaranteed template variable contract               #
# (docs/reference/template-contract.md in the framework repository). This bootstrap             #
# intentionally stays minimal: the communicator connects as the source AMI's default user       #
# (${deploy_user_name}) with the Packer-generated temporary keypair, and configuration is       #
# applied by the Ansible provisioner. Do not bake credentials or secrets into user data — it    #
# is readable from the instance metadata service for the life of the build instance.            #
# ============================================================================================= #

timezone: ${os_timezone}
locale: ${os_language}

# Ensure Ansible's default interpreter discovery finds a Python 3 runtime on first boot.
packages:
  - python3

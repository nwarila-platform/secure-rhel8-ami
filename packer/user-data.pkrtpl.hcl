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

# ansible-core 2.20 needs a modern target interpreter; stock RHEL 8 python3 is 3.6.
packages:
  - python3.12

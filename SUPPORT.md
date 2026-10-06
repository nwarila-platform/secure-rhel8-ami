# Support

## Supported use case

This repository supports the image factory it owns: the Packer template under `packer/`, each
image folder under `images/` (the pkrvars, the user-data template, the playbook and the profile
vars files), the workflows around them, and the developer workflow needed to change them safely,
including the SHA pin for the ansible-framework checkout.

Ansible roles are owned by [ansible-framework](https://github.com/nwarila-platform/ansible-framework).

## Out of scope

- Troubleshooting your specific AWS account, VPC, or IAM configuration.
- Ansible role or collection issues (owned by ansible-framework).
- Instances launched from the published AMIs after first boot.

## When requesting help

Include:

- the command you ran (or the workflow run link)
- the Packer and plugin versions (`packer version`, `packer plugins installed`)
- the pinned ansible-framework SHA from `.github/workflows/packer.yaml`
- the exact error output
- the build region and resolved source AMI ID from the build log

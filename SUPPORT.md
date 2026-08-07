# Support

## Supported use case

This repository supports the RHEL 8 AMI inventory it owns, the caller workflows around it,
and the developer workflow needed to change them safely. This includes the committed
pkrvars, the user-data template, the hardening playbook, and the SHA pins for the
framework and ansible-framework checkouts.

Executable build logic (variable contract, normalization, `amazon-ebs` wiring) is owned by
[aws-packer-framework](https://github.com/nwarila-platform/aws-packer-framework); Ansible
roles are owned by [ansible-framework](https://github.com/nwarila-platform/ansible-framework).

## Out of scope

- Troubleshooting your specific AWS account, VPC, or IAM configuration.
- Framework build-logic issues (owned by aws-packer-framework).
- Ansible role or collection issues (owned by ansible-framework).
- Instances launched from the published AMIs after first boot.

## When requesting help

Include:

- the command you ran (or the workflow run link)
- the Packer and plugin versions (`packer version`, `packer plugins installed`)
- the pinned framework and ansible-framework SHAs from `.github/workflows/packer.yaml`
- the exact error output
- the build region and resolved source AMI ID from the build log

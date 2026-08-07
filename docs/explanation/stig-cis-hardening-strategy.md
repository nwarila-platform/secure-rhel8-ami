# STIG/CIS Hardening Strategy

This repository targets RHEL 8 AMIs that satisfy both the DISA STIG and the CIS
benchmark. Hardening is applied at build time by the aws-packer-framework Ansible
provisioner running consumer-owned plays with roles from
[ansible-framework](https://github.com/nwarila-platform/ansible-framework).

## Layering

1. **Base image** — the official Red Hat RHEL 8.10 AMI, resolved through an
   owner-scoped filter (`owners = ["309956199498"]`). Unscoped filters are rejected
   by the framework at validate time.
2. **Build-time posture** — the framework enforces IMDSv2 (`http_tokens = required`),
   encrypts build and AMI volumes, and connects with a Packer-generated temporary
   keypair; no credentials are baked into the image.
3. **Bootstrap** — [packer/rhel-8.yml](../../packer/rhel-8.yml) dispatches through
   ansible-framework's `os_bootstrap` role. RedHat-family hosts route to
   `RedHat_Rocky_8`, whose strict assertion accepts RHEL/Rocky 8 and rejects
   anything else.
4. **Benchmark roles** — STIG and CIS hardening roles are layered onto the playbook
   from ansible-framework as they become available. The playbook is the single
   integration point; adding a role does not change the framework contract.

## Known Limits

- **Partition layout.** STIG controls requiring separate `/home`, `/tmp`, `/var`,
  `/var/log`, and `/var/log/audit` partitions cannot be satisfied by post-boot
  hardening of the stock single-root-volume AMI. Until a custom-partitioned source
  AMI exists, these controls are documented exceptions.
- **Boot mode / NitroTPM.** The `amazon-ebs` builder inherits boot mode from the
  source AMI and cannot register NitroTPM support. Forcing UEFI or TPM would
  require an `ebssurrogate` migration in the framework.
- **Verification.** Compliance scoring (e.g. OpenSCAP against the RHEL 8 STIG and
  CIS profiles) is not yet wired into the build. When it lands, it should run as a
  post-hardening play and publish results with the build diagnostics.

# STIG/CIS Hardening Strategy

This repository targets RHEL 8 AMIs that satisfy both the DISA STIG and the CIS
benchmark, with hardening applied at build time by the aws-packer-framework Ansible
provisioner running consumer-owned plays with roles from
[ansible-framework](https://github.com/nwarila-platform/ansible-framework). No
benchmark role runs in the build yet: the published image's posture, measured below, is a
patched stock RHEL with the STIG partition layout and mount options, a package strip and no
credentials or identity state.

## Layering

1. **Base image** — the official Red Hat RHEL 8.10 AMI, resolved through an
   owner-scoped filter (`owners = ["309956199498"]`). Unscoped filters are rejected
   by the framework at validate time.
2. **Build-time posture** — the framework enforces IMDSv2 (`http_tokens = required`),
   encrypts build and AMI volumes, and connects with a Packer-generated temporary
   keypair; no credentials are baked into the image.
3. **Bootstrap** — [packer/rhel-8.yml](../../packer/rhel-8.yml) first baselines the
   instance on the latest available packages, then dispatches through
   ansible-framework's `os_bootstrap` role. RedHat-family hosts route to
   `RedHat_Rocky_8`, whose strict assertion accepts RHEL/Rocky 8 and rejects
   anything else.
4. **Partition layout** — the playbook's assembly play partitions a blank surrogate
   volume into the STIG layout (EFI system partition, `/boot`, and an LVM volume group
   with separate `/home`, `/opt`, `/tmp`, `/var`, `/var/tmp`, `/var/log` and
   `/var/log/audit`), copies the configured root in with credential and state excludes,
   installs the signed UEFI bootloader, and hands the volume to the framework's
   `amazon-ebssurrogate` source, which registers it UEFI-only.
5. **Benchmark roles** — STIG and CIS hardening roles are layered onto the playbook
   from ansible-framework as they become available. The playbook is the single
   integration point; adding a role does not change the framework contract.
6. **Verification** — the playbook evaluates the assembled image offline against the
   STIG profile with `oscap-chroot` and fetches the ARF and HTML report into the build
   evidence artifact. The workflow then launches a canary instance from the candidate
   and reads its serial console for: an EFI boot, the nine STIG mount points present,
   `noexec` on `/tmp`, `/var/tmp`, `/var/log` and `/var/log/audit`, no non-empty
   `authorized_keys` for root or any home, no `packer` user, the newest installed
   kernel running, and the five service-state STIG rules (`sshd`, `auditd`, `rsyslog`
   enabled; `kdump`, `debug-shell` disabled), which the canary re-evaluates on the
   running system because the offline scan reported four of them as `unknown` on the
   measured image. Only a candidate that reports `PASS` is tagged as published.

## Measured posture

OpenSCAP evaluation of the image published on 2026-08-11 against
`xccdf_org.ssgproject.content_profile_stig`:

| Outcome | Rules |
|---|---:|
| pass | 126 |
| fail | 214 |
| error | 1 |
| score | 42.1% |

Counted by rule-id prefix, the 215 failing or erroring rules include 73 `audit*`, 28 `sysctl_*`,
15 `sshd_*` and 7 `grub2_*` rules; the other 92 are not grouped here.

Only the STIG profile is evaluated today; a CIS-specific count needs a second
evaluation against the CIS profile.

## Known limits

- **No benchmark role in the build.** The score above is what the STIG partition layout and
  mount options, the package strip and a patched stock image achieve. Raising it is the work
  of the benchmark roles.
- **Loaded policy is not verified.** The scan reads files; whether the kernel loaded
  every rule at first boot is not yet checked by the canary.
- **The compliance scan is report-only.** Rule failures do not fail the build; the
  vulnerability gate (fixable Critical/High CVEs) does.

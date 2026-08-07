# Secure RHEL 8 AMI

[![PR Verify](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/pr-verify.yaml/badge.svg)](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/pr-verify.yaml)
[![Security](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/security.yaml/badge.svg)](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/security.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Consumer repository for [aws-packer-framework](https://github.com/nwarila-platform/aws-packer-framework): builds and
publishes hardened RHEL 8 AMIs for this account on the DISA STIG / CIS compliance track. This repo is data-plus-caller
by design — it owns the RHEL 8 Packer inventory, the first-boot user-data template, the hardening playbook, and the
caller workflows; the framework owns all executable build logic.

## Ownership Model

| Layer | Owner | Where |
|-------|-------|-------|
| Packer orchestration, variable contract, `amazon-ebs` builder | [aws-packer-framework](https://github.com/nwarila-platform/aws-packer-framework) | SHA-pinned checkout in CI |
| Source AMI pin and audit trail | This repo | [packer/systems.auto.pkrvars.hcl](packer/systems.auto.pkrvars.hcl) |
| First-boot user data | This repo | [packer/user-data.pkrtpl.hcl](packer/user-data.pkrtpl.hcl) |
| Hardening playbook | This repo | [packer/rhel-8.yml](packer/rhel-8.yml) |
| Ansible roles (os_bootstrap, hardening) | [ansible-framework](https://github.com/nwarila-platform/ansible-framework) | SHA-pinned checkout in CI |

## How a Build Works

1. CI checks out `aws-packer-framework` and `ansible-framework` at SHA-pinned refs.
2. Consumer files (`systems.auto.pkrvars.hcl`, `user-data.pkrtpl.hcl`, `rhel-8.yml`) are synced into the framework's
   `packer/` working directory; the `.auto.pkrvars.hcl` suffix makes Packer load the inventory automatically.
3. The framework resolves the owner-scoped official Red Hat RHEL 8.10 source AMI (owner `309956199498`), launches the
   build instance with IMDSv2 enforced and encrypted EBS volumes, and connects as `ec2-user` with a Packer-generated
   temporary keypair.
4. The Ansible provisioner runs [packer/rhel-8.yml](packer/rhel-8.yml), which dispatches through ansible-framework's
   `os_bootstrap` role (RedHat-family hosts route to `RedHat_Rocky_8`, whose strict assertion accepts RHEL/Rocky 8).
   STIG and CIS hardening roles are layered on from ansible-framework as they land.
5. The framework registers a timestamped, tagged, encrypted AMI (`secure-rhel8-<timestamp>`) and writes the build
   manifest.

See [docs/explanation/stig-cis-hardening-strategy.md](docs/explanation/stig-cis-hardening-strategy.md) for the
compliance approach and its known limits.

## CI/CD Pipeline

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| PR Verify | Every PR to `main` (and merge queue) | actionlint, pre-commit gates, playbook syntax check, composed `packer validate` against the SHA-pinned framework |
| Packer Build (AWS) | Push to `main` touching `packer/**` (gated by `vars.PACKER_BUILD_ENABLED`) or `workflow_dispatch` | Assumes the OIDC build role, syncs consumer files into the framework checkout, runs `packer validate` + `packer build` |
| Security | Push/PR to `main`, merge queue, weekly schedule | Org `reusable-iac-security`, `reusable-codeql`, and `reusable-scorecard` reusables |
| Repo Hygiene | PR to `main`, merge queue, weekly schedule | Org `reusable-repo-hygiene` policy |
| Release Please | Push to `main` (opt-in via `RELEASE_PLEASE_ON_PUSH`) or `workflow_dispatch` | Changelog and release automation |

## Required Configuration

Before the first live build:

| Kind | Name | Purpose |
|------|------|---------|
| Environment secret (`packer-build`) | `AWS_PACKER_ROLE_ARN` | Build role ARN (role itself is workflow-managed by `iam.yml`) |
| Environment secret (`iam-apply`) | `AWS_IAM_ROLE_ARN` | IAM management role ARN (operator-tier object) assumed by `iam.yml` |
| Repo variable | `AWS_REGION` | Build region (defaults to `us-east-1`) |
| Repo variable | `PACKER_BUILD_ENABLED` | Set `true` to allow push-triggered builds; `workflow_dispatch` works regardless |
| Repo variable | `DEPLOY_USER_NAME` | Optional; defaults to `ec2-user` |

The build authenticates exclusively through GitHub OIDC role assumption — no static access keys exist in this repository
or its secrets. Repo-tier IAM (the build role and policy) is reconciled by the `AWS IAM` workflow with weekly drift
detection; only the governance layer (permissions boundary, management role) is operator-applied, once. See
[docs/reference/aws-iam/](docs/reference/aws-iam/) for the two-tier model and the anti-escalation chain.

## Local Development

```bash
pre-commit install
pre-commit install --hook-type commit-msg
pre-commit run --all-files
```

For a manual end-to-end build from a workstation, see
[docs/runbooks/manual-packer-build.md](docs/runbooks/manual-packer-build.md).

## Consuming the AMIs

Downstream Terraform resolves the newest published image by name prefix and tags:

```hcl
data "aws_ami" "secure_rhel8" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["secure-rhel8-*"]
  }

  filter {
    name   = "tag:ManagedBy"
    values = ["aws-packer-framework"]
  }
}
```

## License

This project is licensed under the [MIT License](LICENSE).

# Secure RHEL 8 AMI

[![PR Verify](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/pr-verify.yaml/badge.svg)](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/pr-verify.yaml)
[![Security](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/security.yaml/badge.svg)](https://github.com/nwarila-platform/secure-rhel8-ami/actions/workflows/security.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Image factory for this account's hardened RHEL 8 AMIs on the DISA STIG / CIS compliance track. The repository owns the
shared Packer template under `packer/`, one folder per image under `images/` (the source AMI selection, the first-boot user
data, the build playbook and the profile vars files), and the workflows that build, verify and publish; the Ansible
roles the playbook includes come from [ansible-framework](https://github.com/nwarila-platform/ansible-framework) at a
SHA-pinned ref.

## Ownership Model

| Layer | Owner | Where |
|-------|-------|-------|
| Packer template: sources (`amazon-ebssurrogate`, `amazon-ebs`), variable contract, provisioner wiring, manifest | This repo | [packer/](packer/) |
| Image inputs: source AMI selection (owner-scoped name filter, newest match; `ami_id` left null) and its audit trail, first-boot user data, build playbook, profile vars | This repo, one folder per image | [images/rhel-8/](images/rhel-8/) |
| Ansible roles (os_bootstrap, hardening) | [ansible-framework](https://github.com/nwarila-platform/ansible-framework) | SHA-pinned checkout in CI |

## How a Build Works

1. CI checks out `ansible-framework` at a SHA-pinned ref inside the repository checkout.
2. For each matrix entry (image, profile, source), Packer runs from `packer/` and loads the image's
   `images/<image>/<image>.pkrvars.hcl` and `images/<image>/profiles/<profile>.yml` by path.
3. The template resolves the owner-scoped official Red Hat RHEL 8.10 source AMI (owner `309956199498`), launches the
   build instance with IMDSv2 enforced and encrypted EBS volumes, and connects as `ec2-user` with a Packer-generated
   temporary keypair.
4. The Ansible provisioner runs [images/rhel-8/playbook.yml](images/rhel-8/playbook.yml), which dispatches through
   ansible-framework's `os_bootstrap` role (RedHat-family hosts route to `RedHat_Rocky_8`, whose strict assertion
   accepts RHEL/Rocky 8). STIG and CIS hardening roles are layered on from ansible-framework as they land.
5. The template registers a timestamped, tagged, encrypted AMI (`secure-rhel8-<timestamp>`) and writes the build
   manifest.

See [docs/explanation/stig-cis-hardening-strategy.md](docs/explanation/stig-cis-hardening-strategy.md) for the
compliance approach and its known limits.

## CI/CD Pipeline

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| PR Verify | Every PR to `main` (and merge queue) | actionlint, pre-commit gates, then for every image folder and profile: playbook syntax check and `packer validate` from `packer/` |
| Packer Build (AWS) | Push to `main` touching `packer/**`, `images/**` or `.github/workflows/packer.yaml` (gated by `vars.PACKER_BUILD_ENABLED`), or `workflow_dispatch` | Per matrix entry: assumes the OIDC build role, runs `packer validate` + `packer build` from `packer/` with the image's inputs |
| Security | Push/PR to `main`, merge queue, weekly schedule (Mondays 08:00 UTC), `branch_protection_rule`, `workflow_dispatch` | Org `reusable-iac-security`, `reusable-codeql`, and `reusable-scorecard` reusables |
| Repo Hygiene | PR to `main`, merge queue, weekly schedule (Mondays 08:00 UTC), `workflow_dispatch` | Org `reusable-repo-hygiene` policy |
| Release Please | Push to `main` (opt-in via `RELEASE_PLEASE_ON_PUSH`) or `workflow_dispatch` | Changelog and release automation |
| AWS IAM | PR touching `docs/reference/aws-iam/**`, the two IAM scripts or `.github/workflows/iam.yml`, and push to `main` touching the first three (gate job); weekly schedule (Mondays 07:23 UTC) and `workflow_dispatch` with `plan`, `apply` or `check-drift` (manage job) | Shell syntax and the offline substitution gate; `bootstrap-iam.sh --tier repo` against live AWS |

## Required Configuration

Before the first live build:

| Kind | Name | Purpose |
|------|------|---------|
| Environment secret (`packer-build`) | `AWS_PACKER_ROLE_ARN` | Build role ARN (role itself is workflow-managed by `iam.yml`) |
| Environment secret (`iam-apply`) | `AWS_IAM_ROLE_ARN` | Role ARN assumed by `iam.yml`; the non-admin role's trust is the one that admits `iam.yml` (the `-admin` trust admits only the SSO broker) |
| Repo variable | `AWS_REGION` | Build region (defaults to `us-east-1`) |
| Repo variable | `PACKER_BUILD_ENABLED` | Set `true` to allow push-triggered builds; `workflow_dispatch` works regardless |
| Repo variable | `DEPLOY_USER_NAME` | Optional; defaults to `ec2-user` |

The build authenticates exclusively through GitHub OIDC role assumption — no static access keys exist in this repository
or its secrets. Repo-tier IAM (the non-admin role and the `packer-build` and `packer-publish` policies) is reconciled by
the `AWS IAM` workflow with weekly drift detection; the operator tier (the boundary, `iam-manage`, `iam-admin`
and the `-admin` role) is applied by hand with `bootstrap-iam.sh --tier operator`. See
[docs/reference/aws-iam/](docs/reference/aws-iam/) for the two-tier model and the anti-escalation chain.

## Local Development

```bash
pre-commit install
pre-commit install --hook-type commit-msg
pre-commit run --all-files
```

For validating the Packer configuration from a workstation, and for running a build by dispatch, see
[docs/runbooks/manual-packer-build.md](docs/runbooks/manual-packer-build.md).

## Consuming the AMIs

Downstream Terraform resolves the newest image the build has registered, by name prefix and tags. The filter does
not yet distinguish a canary-verified image from a candidate: both carry these tags from registration.

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

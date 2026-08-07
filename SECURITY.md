# Security Policy

## Supported Versions

This repository is currently in a pre-1.0 state while the first hardened image line is
established. The supported security surface is:

- the current `main` branch
- the latest tagged release, once release automation starts publishing real versions

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, report them via email to **reports@nicholaswarila.com** with the
following information:

- Description of the vulnerability
- Steps to reproduce (or proof-of-concept)
- Affected versions
- Any potential mitigations you've identified

### What to expect

| Milestone | Target |
|-----------|--------|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 7 days |
| Fix or mitigation | Within 30 days (severity-dependent) |

You will receive updates at each milestone. If the vulnerability is accepted, you will
be credited in the release notes unless you prefer to remain anonymous.

## Coordinated Disclosure

We follow a coordinated disclosure model:

1. Reporter submits the vulnerability privately.
2. We acknowledge receipt and begin investigation.
3. We develop and test a fix.
4. We release the fix and publish an advisory.
5. Reporter is free to publish details after the fix is released.

We ask that you give us reasonable time to address the issue before any public
disclosure. We will work with you to agree on a timeline.

## Scope

The following are **in scope** for security reports:

- Inventory values that weaken the published AMIs (source AMI pins, metadata
  options, encryption settings)
- Hardening playbook gaps that leave a claimed control unenforced
- Secrets or credentials exposed in workflows, user data, or build artifacts
- CI/CD pipeline vulnerabilities (workflow injection, secret leakage, OIDC role misuse)

The following are **out of scope**:

- Vulnerabilities in the framework's executable build logic — report those to
  [aws-packer-framework](https://github.com/nwarila-platform/aws-packer-framework/blob/main/SECURITY.md)
- Vulnerabilities in upstream dependencies (Packer, Ansible, RHEL, AWS services)
- Denial of service against build infrastructure

## Security Features

- **No static credentials** — builds authenticate via GitHub OIDC role assumption only
- **SHA-pinned dependencies** — the framework, ansible-framework, GitHub Actions, and
  validation tooling are all pinned by commit SHA or verified checksum
- **Owner-scoped source AMI** — the base image resolves only from Red Hat's official
  AMI account
- **IMDSv2 and EBS encryption** enforced through the committed inventory
- **Secret scanning** via Gitleaks at pre-commit and in the org Security workflow

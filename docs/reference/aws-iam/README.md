# AWS IAM — roles and policies (secure-rhel8-ami)

**Type**: Reference (Diátaxis). The IAM used by this repository's AMI builds. Cloned from the
[`windows-wsus` IAM reference](https://github.com/nwarila-platform/windows-wsus/blob/main/docs/reference/aws-iam/README.md)
(gates matured in `pdq-deploy-inventory`) and narrowed to the Packer build lifecycle — read
that document's substitution contract before applying anything here; its rules apply unchanged.

Unlike the siblings, the build boundary here is **workflow-managed**: `.github/workflows/iam.yml`
assumes a dedicated management role via OIDC and runs `scripts/bootstrap-iam.sh` (materialize →
substitution gate → Access Analyzer → plan/apply/check-drift, weekly scheduled drift detection).
Only the governance layer stays operator-applied.

## Two tiers

| Tier | Objects | Applied by | Why |
|---|---|---|---|
| repo | `secure-rhel8-ami_packer-build` policy · `github_nwarila-platform_secure-rhel8-ami` role (trust, boundary attachment, policy attachment) | `iam.yml` → `bootstrap-iam.sh --tier repo` via OIDC | Day-to-day IAM changes ride PRs and the workflow |
| operator | `secure-rhel8-ami_boundary` · `secure-rhel8-ami_iam-manage` · `github_nwarila-platform_secure-rhel8-ami-iam` role | `bootstrap-iam.sh --tier operator --profile <sso>` — deliberately, never from CI | The workflow must never write its own authority |

The anti-escalation chain: the management role can manage **only** the build role and build
policy; it can attach **only** this repo's policy (`iam:PolicyARN` condition); it can create or
re-bound the build role **only** carrying the permissions boundary (`iam:PermissionsBoundary`
condition); it carries explicit Denies on itself, its own policy, and the boundary; and the
boundary caps the build role's effective permissions to region-pinned EC2 actions even if the
build policy document were rewritten wider. The account OIDC provider is account Layer-0,
operator-owned, not managed here.

## Substitution contract

Every per-environment value in these sources is a `<placeholder>`. Nothing here is a real
identifier: a `<...>` token can never match a real ARN or account, so an unsubstituted
placeholder fails closed. The dangerous failure is a *partial* substitution — a sibling
repository's value left in one condition fails open and silently.

| Placeholder | Substitute with | Source of truth |
|---|---|---|
| `<account-id>` | the 12-digit AWS account id | `aws sts get-caller-identity` |
| `<repository-id>` | this repo's immutable GitHub repository id | `gh api repos/nwarila-platform/secure-rhel8-ami --jq .id` |
| `<owner-id>` | the `nwarila-platform` org id | `gh api orgs/nwarila-platform --jq .id` |
| `<region>` | the build region | the build plan (`us-east-1`) |
| `<vpc-id>` | the build VPC | `aws ec2 describe-vpcs` — one VPC account-wide, shared by all siblings |

`<repository-id>` is the one that can hurt you: it is the sole authorization key for the
tag-gated lifecycle statements (terminate, volume/snapshot mutation). A sibling's id left in
any statement gives this repository's CI role destroy authority over that sibling's tagged
resources. Substitute it everywhere in one operation.

## Role-to-policy map

| Role | Trust source | Policies | Boundary | Purpose |
|---|---|---|---|---|
| `github_nwarila-platform_secure-rhel8-ami` | `roles/github_nwarila-platform_secure-rhel8-ami.trust.json` | `secure-rhel8-ami_packer-build` | `secure-rhel8-ami_boundary` | CI Packer build: launch, provision, snapshot, register, clean up |
| `github_nwarila-platform_secure-rhel8-ami-iam` | `roles/github_nwarila-platform_secure-rhel8-ami-iam.trust.json` | `secure-rhel8-ami_iam-manage` | — (operator-tier object) | `iam.yml` workflow: reconcile the repo-tier objects with the tracked source |

Each trust is bounded to this repository's immutable `repository_id`, both OIDC subject forms
(plain and ID-embedded — see the windows-wsus reference for the CloudTrail-proven rationale),
and exactly one `job_workflow_ref`: `packer.yaml` for the build role, `iam.yml` for the
management role — so neither workflow can assume the other's role.

## Design notes

- **Identity tag**: `nwarila:management:repository-id = <repository-id>`, applied by Packer's
  `run_tags`/`snapshot_tags` at create time (`aws:RequestTag` on the instance, volume, and
  snapshot legs) and required by `ec2:ResourceTag` on every mutating action. The committed
  inventory carries the tag; removing it from `systems.auto.pkrvars.hcl` fails the build closed.
- **Encryption required**: the RunInstances volume leg requires `ec2:Encrypted: true` and caps
  volume size at 64 GiB — the build uses a 30 GiB root plus a 30 GiB surrogate.
- **Instance types pinned** to `t3.medium` / `t3.large`, matching the committed inventory.
- **No credential on the build instance**: the role attaches no instance profile, and the
  variable contract has no static-key inputs; the AMI itself therefore carries no path to AWS
  credentials.

## Known residuals (accepted, recorded rather than hidden)

- **Temporary key pair and security group are name-scoped, not tag-scoped** (`packer_*` ARN
  prefix for key pairs; region+VPC pin for security groups). Packer creates both before any
  tag exists and EC2 offers no create-time tag condition on these legs through this builder.
- **Volume and snapshot legs are region-scoped, not tag-gated**: the surrogate builder's
  volume/snapshot tagging timing is not create-time-guaranteed, and a `ResourceTag` condition
  here would fail a build closed twenty minutes in. Tighten with CloudTrail evidence from real
  runs (the windows-wsus "proven live" method) rather than by assumption.
- **`ec2:CreateTags` is resource-type-scoped but not tag-value-gated**: Packer applies AMI and
  snapshot tags after creation rather than through create-time tag specifications on
  RegisterImage, so the grant covers the four resource types in-region.
- **`RegisterImage`/`DeregisterImage` are region-scoped**: image ARNs carry no account or tag
  context usable here.

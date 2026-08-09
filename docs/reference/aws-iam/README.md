# AWS IAM — roles and policies (secure-rhel8-ami)

**Type**: Reference (Diátaxis). The IAM used by this repository's AMI builds. Cloned from the
[`windows-wsus` IAM reference](https://github.com/nwarila-platform/windows-wsus/blob/main/docs/reference/aws-iam/README.md)
(gates matured in `pdq-deploy-inventory`) and narrowed to the Packer build lifecycle — read
that document's substitution contract before applying anything here; its rules apply unchanged.

Unlike the siblings, the build boundary here is **workflow-managed**: `.github/workflows/iam.yml`
assumes a dedicated management role via OIDC and runs `scripts/bootstrap-iam.sh` (materialize →
substitution gate → Access Analyzer → plan/apply/check-drift, weekly scheduled drift detection).
Only the governance layer stays operator-applied.

## Two roles, two tiers

Exactly two roles exist: the **non-admin** role GitHub assumes and the **-admin** role the
operator personally assumes through the organization SSO broker.

| Tier | Objects | Applied by | Why |
|---|---|---|---|
| repo | `secure-rhel8-ami_packer-build` policy · non-admin role (trust, boundary attachment, policy attachments) | `iam.yml` → `bootstrap-iam.sh --tier repo` via OIDC | Day-to-day IAM changes ride PRs and the workflow |
| operator | `secure-rhel8-ami_boundary` · `secure-rhel8-ami_iam-manage` · `secure-rhel8-ami_iam-admin` · the `-admin` role | `bootstrap-iam.sh --tier operator --profile <sso>` — personally, never from CI | The workflow must never write its own authority |

The anti-escalation chain: the non-admin role's `iam-manage` grant can manage **only** the
build policy and the role's own trust/boundary/attachments; it can attach **only** this repo's
policies (`iam:PolicyARN` condition); create/re-bound requires the permissions boundary
(`iam:PermissionsBoundary` condition); explicit Denies cover the `-admin` role, the boundary,
and both governance policies; and the boundary caps the role's effective permissions —
region-pinned EC2 plus IAM on exactly the two repo-tier objects — even if the build policy
document were rewritten wider. The account OIDC provider is account Layer-0, operator-owned,
not managed here.

## Iterative policy derivation

`secure-rhel8-ami_packer-build` is developed **empirically**: it started as a blank baseline
(`sts:GetCallerIdentity` only) and every statement is added in response to an observed
`UnauthorizedOperation` denial from a real build run — one denial, one commit, one
`iam.yml apply`, re-run. The commit history of the policy file is the least-privilege
derivation record; nothing in it is speculative.

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
| `github_nwarila-platform_secure-rhel8-ami` | `roles/github_nwarila-platform_secure-rhel8-ami.trust.json` | `secure-rhel8-ami_packer-build` · `secure-rhel8-ami_iam-manage` | `secure-rhel8-ami_boundary` | GitHub-assumed: Packer builds (`packer.yaml`) and repo-tier IAM reconciliation (`iam.yml`) |
| `github_nwarila-platform_secure-rhel8-ami-admin` | `roles/github_nwarila-platform_secure-rhel8-ami-admin.trust.json` | `secure-rhel8-ami_packer-build` · `secure-rhel8-ami_iam-admin` | — (operator trust level) | Personally assumed via the SSO broker: local builds, break-glass, and governance-tier applies |

The non-admin trust is bounded to this repository's immutable `repository_id`, both OIDC
subject forms (plain and ID-embedded — see the windows-wsus reference for the
CloudTrail-proven rationale), and exactly two `job_workflow_ref` entries: `packer.yaml` and
`iam.yml`. The `-admin` trust admits only the organization SSO broker, bounded to the
permission-set hash.

## Design notes

- **Identity tag**: `RepositoryId = <repository-id>`, applied by Packer's
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
- **`iam.yml` and `packer.yaml` share the non-admin role** (two-role model, owner decision):
  a compromised build workflow could reach the repo-tier IAM surface. The cap is the trust
  (`job_workflow_ref` limits which workflows assume the role at all), the gated sources, the
  iam-manage Denies, and the boundary ceiling. The role can update its own trust document —
  accepted because the trust source rides the same gated PR path as every other IAM change.
- **`ec2:CreateTags` is resource-type-scoped but not tag-value-gated**: Packer applies AMI and
  snapshot tags after creation rather than through create-time tag specifications on
  RegisterImage, so the grant covers the four resource types in-region.
- **`RegisterImage`/`DeregisterImage` are region-scoped**: image ARNs carry no account or tag
  context usable here.

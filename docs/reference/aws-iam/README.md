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
| repo | `secure-rhel8-ami_packer-build` and `secure-rhel8-ami_packer-publish` policies · non-admin role (trust, boundary attachment, policy attachments) | `iam.yml` → `bootstrap-iam.sh --tier repo` via OIDC | Day-to-day IAM changes ride PRs and the workflow |
| operator | `secure-rhel8-ami_boundary` · `secure-rhel8-ami_iam-manage` · `secure-rhel8-ami_iam-admin` · the `-admin` role | `bootstrap-iam.sh --tier operator --profile <sso>` — personally, never from CI | The workflow must never write its own authority |

The anti-escalation chain: the non-admin role's `iam-manage` grant can manage **only** the
two repo-tier policies (`packer-build`, `packer-publish`) and the role's own trust/boundary/attachments; it can attach **only** this repo's
policies (`iam:PolicyARN` condition); create/re-bound requires the permissions boundary
(`iam:PermissionsBoundary` condition); explicit Denies cover the `-admin` role, the boundary,
and both governance policies; and the boundary caps the role's effective permissions —
region-pinned EC2, IAM on the three repo-tier objects (the two policies and the role) and
`access-analyzer:ValidatePolicy` — even if the build policy document were rewritten wider. The account OIDC provider is account Layer-0, operator-owned,
not managed here.

## Iterative policy derivation

`secure-rhel8-ami_packer-build` and `secure-rhel8-ami_packer-publish` were developed **empirically**:
statements were added in response to `UnauthorizedOperation` denials from real build runs, and the
commit history of the policy files is the derivation record. Not every commit adds exactly one
statement: PR #53 (`55f9906`), for example, added the three canary permissions in one commit.

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
| `<subnet-id>` | the build subnet | `images/rhel-8/rhel-8.pkrvars.hcl` (`vpc_config.subnet_id`) |
| `<source-ami-owner>` | the account that publishes the source AMI | `images/rhel-8/rhel-8.pkrvars.hcl` (`source_ami.owners`, Red Hat's publishing account) |
| `<sso-permission-set>` | the organization SSO permission-set name, `AdministratorAccess` unless overridden; the trust document appends the role's 16-character suffix as a separate wildcard | `scripts/bootstrap-iam.sh` (`SSO_PERMISSION_SET`, default `AdministratorAccess`) |

`<repository-id>` is the one that can hurt you: it is the tag value the ten tag-gated statements
listed under "Identity tag" below test (terminate, image deregistration and snapshot deletion among
them), beside their VPC, attribute or encryption conditions. A sibling's id left in any of them gives
this repository's CI role that authority over the sibling's tagged resources. Substitute it everywhere
in one operation.

## Role-to-policy map

| Role | Trust source | Policies | Boundary | Purpose |
|---|---|---|---|---|
| `github_nwarila-platform_secure-rhel8-ami` | `roles/github_nwarila-platform_secure-rhel8-ami.trust.json` | `secure-rhel8-ami_packer-build` · `secure-rhel8-ami_packer-publish` · `secure-rhel8-ami_iam-manage` | `secure-rhel8-ami_boundary` | GitHub-assumed: Packer builds (`packer.yaml`) and repo-tier IAM reconciliation (`iam.yml`) |
| `github_nwarila-platform_secure-rhel8-ami-admin` | `roles/github_nwarila-platform_secure-rhel8-ami-admin.trust.json` | `secure-rhel8-ami_packer-build` · `secure-rhel8-ami_packer-publish` · `secure-rhel8-ami_iam-admin` | — (operator trust level) | Personally assumed via the SSO broker: local builds, break-glass, and governance-tier applies |

The non-admin trust is bounded to this repository's immutable `repository_id`, both OIDC
subject forms (plain and ID-embedded — see the windows-wsus reference for the
CloudTrail-proven rationale), and exactly two `job_workflow_ref` entries: `packer.yaml` and
`iam.yml`. The `-admin` trust admits only the organization SSO broker, bounded to the
permission-set hash.

## Design notes

- **Identity tag**: `RepositoryId = <repository-id>`, applied by Packer from the committed inventory's
  `tags`, `run_tags` and `snapshot_tags`, and tested by `ec2:ResourceTag/RepositoryId` on ten statements:
  `TempSecGroupLifecycleOurs`, `RunSecGroupLegOurs`, `InstanceLifecycleOnlyOurs`, `EnaFlagOnOurInstances` and
  `RegisterImageSnapshotLeg` in the build policy; `RunImageLegOurs`, `ReadOurConsoleOutput`,
  `SnapshotDeleteOnlyOurs`, `DeregisterOnlyOurImages` and `RetagOurTaggedSnapshots` in the publish policy.
  No other statement carries a tag condition, and none uses `aws:RequestTag`.
- **Encryption required**: the RunInstances volume leg requires `ec2:Encrypted: true` and caps
  volume size at 30 GiB — the build uses a 30 GiB root plus a 30 GiB surrogate.
- **Instance type pinned** to `t3.medium`, matching the committed inventory.
- **No credential on the build instance**: the role attaches no instance profile, and the
  variable contract has no static-key inputs; the AMI itself therefore carries no path to AWS
  credentials.

## Known residuals (accepted, recorded rather than hidden)

- **The temporary key pair is name-scoped, not tag-scoped** (`packer_*` ARN prefix on its create and
  delete legs); it is tagged at creation under `ec2:CreateAction`, but nothing later tests that tag. The
  temporary security group is created in the pinned VPC and tagged at creation; its ingress and delete
  legs require `ec2:ResourceTag/RepositoryId` and the VPC (`TempSecGroupLifecycleOurs`).
- **Volume legs carry no tag condition** (`RunVolumeLegEncrypted` and `SurrogateSnapVolumeLeg`: encryption
  and the 30 GiB cap only), and neither does the `CreateSnapshot` leg (`SurrogateSnapCreateLeg`); the
  plugin sends `snapshot_tags` with the create request, which `TagSnapshotOnCreate` allows under
  `ec2:CreateAction`. The snapshot legs of `RegisterImage`, `DeleteSnapshot` and the snapshot re-tag test
  the tag. Tighten with CloudTrail evidence from real runs (the windows-wsus
  "proven live" method) rather than by assumption.
- **`iam.yml` and `packer.yaml` share the non-admin role** (two-role model, owner decision):
  a compromised build workflow could reach the repo-tier IAM surface. The cap is the trust
  (`job_workflow_ref` limits which workflows assume the role at all), the gated sources, the
  iam-manage Denies, and the boundary ceiling. The role can update its own trust document —
  accepted because the trust source rides the same gated PR path as every other IAM change.
- **`iam-admin` cannot manage `secure-rhel8-ami_packer-publish`**: its `ManageAllRepoPolicies`
  statement lists `packer-build`, the boundary, `iam-manage` and `iam-admin` only, so the
  `-admin` path as documented cannot create or version the publish policy; that policy was
  applied through the workflow path.
- **`ec2:CreateTags` is resource-type-scoped but not tag-value-gated**: Packer applies AMI and
  snapshot tags after creation rather than through create-time tag specifications on
  RegisterImage, so the grant covers six resource types in-region (instance, network interface,
  key pair, security group, snapshot, image): create-time legs under `ec2:CreateAction`, the image
  leg under `aws:ResourceAccount`, the snapshot re-tag leg under the `RepositoryId` tag.
- **`RegisterImage` is region-scoped on its image leg** (`image/*`: an image has no tag at
  registration); its snapshot leg requires the `RepositoryId` tag and encryption. `DeregisterImage`,
  and the canary's `RunInstances` on our images, require `ec2:ResourceTag/RepositoryId`, which Packer
  applies from the inventory's `tags` map right after registration, before the canary; the workflow's
  later `CreateTags` writes only the four publication tags.

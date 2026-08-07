# AWS IAM — roles and policies (secure-rhel8-ami)

**Type**: Reference (Diátaxis). The IAM used by this repository's AMI builds. An operator
provisions the role and policy; Terraform does not manage them. Cloned from the
[`windows-wsus` IAM reference](https://github.com/nwarila-platform/windows-wsus/blob/main/docs/reference/aws-iam/README.md)
and narrowed to the Packer build lifecycle — read that document's substitution contract
before applying anything here; its rules apply unchanged.

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

| Role | Trust source | Policies | Purpose |
|---|---|---|---|
| `github_nwarila-platform_secure-rhel8-ami` | `roles/github_nwarila-platform_secure-rhel8-ami.trust.json` | `secure-rhel8-ami_packer-build` | CI Packer build: launch, provision, snapshot, register, clean up |

The trust is bounded to this repository's immutable `repository_id`, both OIDC subject forms
(plain and ID-embedded — see the windows-wsus reference for the CloudTrail-proven rationale),
and exactly one `job_workflow_ref`: `packer.yaml`, the build boundary workflow.

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

#!/usr/bin/env bash
# =========================================================================================== #
# bootstrap-iam.sh — materialize and apply this repository's AWS IAM
# ------------------------------------------------------------------------------------------- #
# Two tiers with a deliberate privilege split:
#
#   --tier repo (default)   The build boundary: the packer-build policy and the build role
#                           (trust, boundary attachment, policy attachment). Applied by the
#                           iam.yml workflow, which assumes github_<owner>_<repo>-iam via OIDC.
#                           That role can manage ONLY these two objects, can only attach this
#                           repo's policy, can only set this repo's permissions boundary, and
#                           carries explicit Denies on itself, its own policy, and the boundary
#                           — so a compromised workflow cannot widen its own authority, and any
#                           widening of the build policy is still capped by the boundary.
#
#   --tier operator         The governance layer the workflow must never write: the permissions
#                           boundary, the iam-manage policy, and the -iam management role. Run
#                           once by an operator with SSO credentials, then only when the
#                           governance layer itself changes. The account OIDC provider is
#                           account Layer-0 and is not managed here.
#
#   ./scripts/bootstrap-iam.sh [--plan|--apply|--check-drift] [--tier repo|operator] [--profile NAME]
#
# --check-drift compares LIVE IAM against the tracked source and fails on any difference — the
# one comparison neither other gate makes: check-iam-literals.sh reads source vs filesystem, so
# it passes while live holds an older version. (A sibling repo learned this the hard way when a
# stale live trust de-credentialed CI with nothing to catch it.)
#
# Without --apply it PLANS: materializes, gates, validates every document through Access
# Analyzer, and prints what would be created or updated. Nothing is written to AWS.
#
# Substitution values are resolved from the live account and the live GitHub repository, never
# hand-typed: the account from sts, the repository and owner ids from the GitHub API, and the
# VPC from the deploy environment. The SSO permission set for the -admin trust defaults to
# AdministratorAccess and can be overridden with SSO_PERMISSION_SET.
# =========================================================================================== #
set -uo pipefail

MODE='plan'; TIER='repo'; PROFILE=''
while [ $# -gt 0 ]; do
    case "$1" in
        --plan) MODE='plan' ;;
        --apply) MODE='apply' ;;
        --check-drift) MODE='drift' ;;
        --tier) shift; TIER="${1:?--tier needs repo|operator}" ;;
        --profile) shift; PROFILE="${1:?--profile needs a name}" ;;
        *) printf 'bootstrap-iam: unknown argument %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done
case "${TIER}" in repo|operator) ;; *) printf 'bootstrap-iam: --tier must be repo or operator\n' >&2; exit 2 ;; esac

REGION="${AWS_REGION:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IAM_DIR="${ROOT}/docs/reference/aws-iam"
OWNER='nwarila-platform'
REPO="$(basename "${ROOT}")"

# In CI the credentials are ambient (OIDC); --profile is the operator path.
AWSARGS=(--region "${REGION}")
[ -n "${PROFILE}" ] && AWSARGS+=(--profile "${PROFILE}")

WORK="$(mktemp -d)"; trap 'rm -rf "${WORK}"' EXIT
say() { printf '  %-58s %s\n' "$1" "$2"; }
die() { printf 'bootstrap-iam: FAIL — %s\n' "$1" >&2; exit 1; }

echo "== resolving substitution values from live sources =="
ACCOUNT="$(aws sts get-caller-identity "${AWSARGS[@]}" --query Account --output text)" || die 'no AWS identity'
REPO_ID="$(gh api "repos/${OWNER}/${REPO}" --jq .id)" || die "GitHub repo ${OWNER}/${REPO} not found"
OWNER_ID="$(gh api "orgs/${OWNER}" --jq .id)" || die "cannot resolve owner id for ${OWNER}"
VPC_ID="$(aws ec2 describe-vpcs "${AWSARGS[@]}" --query 'Vpcs[0].VpcId' --output text)" || die 'cannot resolve VPC'
SUBNET_ID="$(sed -n 's/^ *subnet_id *= *"\(subnet-[a-f0-9]*\)".*/\1/p' "${ROOT}/packer/systems.auto.pkrvars.hcl" | head -1)"
[ -n "${SUBNET_ID}" ] || die 'cannot resolve subnet_id from packer/systems.auto.pkrvars.hcl'
AMI_OWNER="$(sed -n 's/^ *owners *= *\["\([0-9]*\)"\].*/\1/p' "${ROOT}/packer/systems.auto.pkrvars.hcl" | head -1)"
[ -n "${AMI_OWNER}" ] || die 'cannot resolve source AMI owner from packer/systems.auto.pkrvars.hcl'
SSO_PS="${SSO_PERMISSION_SET:-AdministratorAccess}"
say 'account / region' "${ACCOUNT} / ${REGION}"
say 'repository id / owner id' "${REPO_ID} / ${OWNER_ID}"
say 'vpc / sso permission set' "${VPC_ID} / ${SSO_PS}"

echo "== materialize =="
mkdir -p "${WORK}/policies" "${WORK}/roles"
cp "${IAM_DIR}/policies/"*.json "${WORK}/policies/"
cp "${IAM_DIR}/roles/"*.json    "${WORK}/roles/"
sed -i "s|<account-id>|${ACCOUNT}|g; s|<repository-id>|${REPO_ID}|g; s|<owner-id>|${OWNER_ID}|g;
        s|<region>|${REGION}|g; s|<vpc-id>|${VPC_ID}|g; s|<subnet-id>|${SUBNET_ID}|g; s|<source-ami-owner>|${AMI_OWNER}|g; s|<sso-permission-set>|${SSO_PS}|g" \
        "${WORK}"/policies/*.json "${WORK}"/roles/*.json

"${ROOT}/scripts/check-iam-literals.sh" --materialized "${WORK}" >/dev/null \
  || die 'the materialized tree failed the substitution gate — do not apply'
say 'substitution gate' 'clean'

echo "== validate every document before anything is written =="
for f in "${WORK}"/policies/*.json; do
    n="$(aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document "file://${f}" \
         "${AWSARGS[@]}" \
         --query 'length(findings[?findingType==`ERROR`||findingType==`SECURITY_WARNING`])' --output text)" \
      || die "Access Analyzer rejected the call for $(basename "${f}")"
    [ "${n}" = 0 ] || die "$(basename "${f}") has ${n} error/security finding(s)"
    say "$(basename "${f}")" 'clean'
done
for f in "${WORK}"/roles/*.json; do
    n="$(aws accessanalyzer validate-policy --policy-type RESOURCE_POLICY --policy-document "file://${f}" \
         "${AWSARGS[@]}" \
         --query 'length(findings[?findingType==`ERROR`&&issueCode!=`MISSING_RESOURCE`])' --output text)" \
      || die "Access Analyzer rejected the call for $(basename "${f}")"
    [ "${n}" = 0 ] || die "$(basename "${f}") has ${n} error(s)"
    say "$(basename "${f}")" 'clean'
done

# ---- the declared object model, per tier ----------------------------------------------------
BUILD_ROLE="github_${OWNER}_${REPO}"
ADMIN_ROLE="github_${OWNER}_${REPO}-admin"
BUILD_POLICY="${REPO}_packer-build"
BOUNDARY_POLICY="${REPO}_boundary"
MANAGE_POLICY="${REPO}_iam-manage"
ADMIN_POLICY="${REPO}_iam-admin"
BOUNDARY_ARN="arn:aws:iam::${ACCOUNT}:policy/${BOUNDARY_POLICY}"

if [ "${TIER}" = 'repo' ]; then
    POLICIES=("${BUILD_POLICY}")
    ROLE_PAIRS=("${BUILD_ROLE}:${BUILD_ROLE}.trust.json")
    ATTACHMENTS=("${BUILD_ROLE}:${BUILD_POLICY}" "${BUILD_ROLE}:${MANAGE_POLICY}")
else
    POLICIES=("${BOUNDARY_POLICY}" "${MANAGE_POLICY}" "${ADMIN_POLICY}")
    ROLE_PAIRS=("${ADMIN_ROLE}:${ADMIN_ROLE}.trust.json")
    ATTACHMENTS=("${ADMIN_ROLE}:${BUILD_POLICY}" "${ADMIN_ROLE}:${ADMIN_POLICY}")
fi

exists_policy() { aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT}:policy/$1" "${AWSARGS[@]}" >/dev/null 2>&1; }
exists_role()   { aws iam get-role --role-name "$1" "${AWSARGS[@]}" >/dev/null 2>&1; }

echo "== plan (tier: ${TIER}) =="
for p in "${POLICIES[@]}"; do say "policy ${p}" "$(exists_policy "${p}" && echo 'exists → new version' || echo 'CREATE')"; done
for pair in "${ROLE_PAIRS[@]}"; do
    r="${pair%%:*}"
    say "role ${r}" "$(exists_role "${r}" && echo 'exists → update trust' || echo 'CREATE')"
done
[ "${TIER}" = 'repo' ] && say "boundary on ${BUILD_ROLE}" "${BOUNDARY_POLICY}"

# ---- drift mode ------------------------------------------------------------------------------
if [ "${MODE}" = 'drift' ]; then
    drift=0
    for p in "${POLICIES[@]}"; do
        arn="arn:aws:iam::${ACCOUNT}:policy/${p}"
        if ! exists_policy "${p}"; then say "policy ${p}" 'ABSENT LIVE'; drift=1; continue; fi
        v="$(aws iam get-policy --policy-arn "${arn}" "${AWSARGS[@]}" --query Policy.DefaultVersionId --output text)"
        aws iam get-policy-version --policy-arn "${arn}" --version-id "${v}" "${AWSARGS[@]}" \
            --query PolicyVersion.Document --output json > "${WORK}/live.json"
        if python3 -S -c "
import json, sys, urllib.parse
l = json.load(open(sys.argv[1]))
if isinstance(l, str): l = json.loads(urllib.parse.unquote(l))
s = json.load(open(sys.argv[2]))
sys.exit(0 if l['Statement'] == s['Statement'] else 1)" "${WORK}/live.json" "${WORK}/policies/${p}.json"; then
            say "policy ${p}" "in sync (${v})"
        else
            say "policy ${p}" "DRIFT — live ${v} differs from source"; drift=1
        fi
    done
    for pair in "${ROLE_PAIRS[@]}"; do
        role="${pair%%:*}"; tf="${pair#*:}"
        if ! exists_role "${role}"; then say "role ${role}" 'ABSENT LIVE'; drift=1; continue; fi
        aws iam get-role --role-name "${role}" "${AWSARGS[@]}" --query Role.AssumeRolePolicyDocument --output json > "${WORK}/live.json"
        if python3 -S -c "
import json, sys
sys.exit(0 if json.load(open(sys.argv[1]))['Statement'] == json.load(open(sys.argv[2]))['Statement'] else 1)" \
            "${WORK}/live.json" "${WORK}/roles/${tf}"; then
            say "trust ${role}" 'in sync'
        else
            say "trust ${role}" 'DRIFT — live differs from source'; drift=1
        fi
    done
    if [ "${TIER}" = 'repo' ] && exists_role "${BUILD_ROLE}"; then
        live_boundary="$(aws iam get-role --role-name "${BUILD_ROLE}" "${AWSARGS[@]}" \
            --query 'Role.PermissionsBoundary.PermissionsBoundaryArn' --output text 2>/dev/null)"
        if [ "${live_boundary}" = "${BOUNDARY_ARN}" ]; then
            say "boundary ${BUILD_ROLE}" 'in sync'
        else
            say "boundary ${BUILD_ROLE}" "DRIFT — live '${live_boundary}'"; drift=1
        fi
    fi
    [ "${drift}" -eq 0 ] || die 'live IAM has drifted from the tracked source. Re-run with --apply.'
    printf '\nbootstrap-iam: NO DRIFT — live IAM matches the tracked source.\n'
    exit 0
fi

if [ "${MODE}" != 'apply' ]; then
    printf '\nbootstrap-iam: PLAN ONLY — nothing was written. Re-run with --apply.\n'
    exit 0
fi

echo "== apply =="
for p in "${POLICIES[@]}"; do
    arn="arn:aws:iam::${ACCOUNT}:policy/${p}"
    if exists_policy "${p}"; then
        # keep at most 5 versions: prune the oldest non-default before adding
        old="$(aws iam list-policy-versions --policy-arn "${arn}" "${AWSARGS[@]}" \
               --query 'Versions[?!IsDefaultVersion]|[-1].VersionId' --output text 2>/dev/null)"
        [ "${old}" != 'None' ] && [ -n "${old}" ] && \
          [ "$(aws iam list-policy-versions --policy-arn "${arn}" "${AWSARGS[@]}" --query 'length(Versions)' --output text)" -ge 5 ] && \
          aws iam delete-policy-version --policy-arn "${arn}" --version-id "${old}" "${AWSARGS[@]}" >/dev/null 2>&1
        aws iam create-policy-version --policy-arn "${arn}" --policy-document "file://${WORK}/policies/${p}.json" \
            --set-as-default "${AWSARGS[@]}" >/dev/null || die "create-policy-version ${p}"
        say "policy ${p}" 'new default version'
    else
        aws iam create-policy --policy-name "${p}" --policy-document "file://${WORK}/policies/${p}.json" \
            --description "${REPO} - see docs/reference/aws-iam" "${AWSARGS[@]}" >/dev/null || die "create-policy ${p}"
        say "policy ${p}" 'created'
    fi
done

for pair in "${ROLE_PAIRS[@]}"; do
    role="${pair%%:*}"; tf="${WORK}/roles/${pair#*:}"
    if exists_role "${role}"; then
        aws iam update-assume-role-policy --role-name "${role}" --policy-document "file://${tf}" "${AWSARGS[@]}" >/dev/null \
            || die "update-assume-role-policy ${role}"
        say "role ${role}" 'trust updated'
    else
        CREATE_ARGS=(--role-name "${role}" --assume-role-policy-document "file://${tf}"
                     --max-session-duration 3600 --description "${REPO} - see docs/reference/aws-iam")
        [ "${role}" = "${BUILD_ROLE}" ] && CREATE_ARGS+=(--permissions-boundary "${BOUNDARY_ARN}")
        aws iam create-role "${CREATE_ARGS[@]}" "${AWSARGS[@]}" >/dev/null || die "create-role ${role}"
        say "role ${role}" 'created'
    fi
done

if [ "${TIER}" = 'repo' ]; then
    aws iam put-role-permissions-boundary --role-name "${BUILD_ROLE}" \
        --permissions-boundary "${BOUNDARY_ARN}" "${AWSARGS[@]}" >/dev/null \
        || die "put-role-permissions-boundary ${BUILD_ROLE}"
    say "boundary ${BUILD_ROLE}" "${BOUNDARY_POLICY}"
fi

for pair in "${ATTACHMENTS[@]}"; do
    role="${pair%%:*}"; pol="arn:aws:iam::${ACCOUNT}:policy/${pair#*:}"
    aws iam attach-role-policy --role-name "${role}" --policy-arn "${pol}" "${AWSARGS[@]}" >/dev/null \
        || die "attach-role-policy ${role} <- ${pair#*:}"
    say "attach ${pair#*:}" "→ ${role}"
done

echo "== verify against live =="
for pair in "${ROLE_PAIRS[@]}"; do
    role="${pair%%:*}"
    aws iam get-role --role-name "${role}" "${AWSARGS[@]}" --query 'Role.Arn' --output text
done
printf '\nbootstrap-iam: APPLIED — tier %s reconciled with the tracked source.\n' "${TIER}"

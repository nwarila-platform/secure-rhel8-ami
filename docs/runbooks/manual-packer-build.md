# Manual Packer Build

Validate the Packer configuration from a workstation; build by dispatching the `Packer Build (AWS)`
workflow. The workflow is the only build path that runs the SBOM and vulnerability gate, the canary
boot, publication tagging and the cleanup of unverified candidates; a workstation `packer build` runs
none of them (the OpenSCAP evaluation is inside the playbook, so it runs in either path). An unfiltered
local build would also build both sources in the template, including the plain `amazon-ebs` one.

## Prerequisites

- Packer 1.15.0
- ansible-core with `ansible-playbook` on PATH
- Git access to `nwarila-platform/ansible-framework`
- `gh` authenticated with permission to dispatch workflows in this repository

## Validate locally

```bash
# 1. Clone this repository, and ansible-framework inside it at the SHA pinned in
#    .github/workflows/packer.yaml. The checkout path matches the pkrvars' roles_path
#    and config_path, which are relative to packer/.
git clone https://github.com/nwarila-platform/secure-rhel8-ami.git
cd secure-rhel8-ami
git clone https://github.com/nwarila-platform/ansible-framework.git
git -C ansible-framework checkout <ansible ref from packer.yaml>

# 2. Export the required Packer variables.
export PKR_VAR_aws_region="us-east-1"
export PKR_VAR_deploy_user_name="ec2-user"

# 3. Validate from the template directory, passing the image's inputs by path.
cd packer
export ANSIBLE_CONFIG="$(pwd)/../ansible-framework/ansible.cfg"
ansible-playbook --syntax-check -i localhost, -c local ../images/rhel-8/playbook.yml
packer init .
packer validate \
  -var-file=../images/rhel-8/rhel-8.pkrvars.hcl \
  -var=ansible_extra_vars_file=../images/rhel-8/profiles/stig.yml \
  -only=amazon-ebssurrogate.packer_image .
```

## Build by dispatch

```bash
gh workflow run packer.yaml --repo nwarila-platform/secure-rhel8-ami --ref main
gh run watch "$(gh run list --repo nwarila-platform/secure-rhel8-ami --workflow packer.yaml \
  --limit 1 --json databaseId --jq '.[0].databaseId')" --repo nwarila-platform/secure-rhel8-ami
```

The run summary reports the vulnerability counts, the canary verdict and, when a new image
is published, its AMI ID and change key. Build evidence (RPM manifest and database, SBOM, vulnerability report, OpenSCAP ARF and HTML
report, canary console log) is attached to the run as the `build-evidence-<image>-<profile>`
artifact; the canary runs in the image folder and writes its log into the same `evidence/`
directory the upload collects.

## Cleanup

The workflow terminates the build instance, the canary and their temporary key pair and
security group, and deregisters a candidate that failed the canary. If a run is cancelled
hard, check for orphaned `packer-build-secure-rhel8` or `canary-secure-rhel8` instances and
`packer_*` or `canary-secure-rhel8-*` security groups in the build region.

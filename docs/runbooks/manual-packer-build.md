# Manual Packer Build

Validate the composed Packer configuration from a workstation; build by dispatching the
`Packer Build (AWS)` workflow. The workflow is the only build path that runs the SBOM and
vulnerability gate, the canary boot, publication tagging and the cleanup of unverified
candidates; a workstation `packer build` runs none of them (the OpenSCAP evaluation is inside
the playbook, so it runs in either path). An unfiltered local build would also build both
framework sources, including the plain `amazon-ebs` one.

## Prerequisites

- Packer 1.15.0
- ansible-core with `ansible-playbook` on PATH
- Git access to `nwarila-platform/aws-packer-framework` and
  `nwarila-platform/ansible-framework`
- `gh` authenticated with permission to dispatch workflows in this repository

## Validate locally

```bash
# 1. Check out the three repositories side by side, frameworks at the pinned SHAs
#    used by .github/workflows/packer.yaml.
git clone https://github.com/nwarila-platform/secure-rhel8-ami.git
git clone https://github.com/nwarila-platform/aws-packer-framework.git
git clone https://github.com/nwarila-platform/ansible-framework.git
git -C aws-packer-framework checkout <framework_ref from packer.yaml>
git -C ansible-framework checkout <ansible ref from packer.yaml>

# 2. Sync consumer files into the framework working directory.
cp -f secure-rhel8-ami/packer/systems.auto.pkrvars.hcl aws-packer-framework/packer/
cp -f secure-rhel8-ami/packer/user-data.pkrtpl.hcl aws-packer-framework/packer/
cp -f secure-rhel8-ami/packer/rhel-8.yml aws-packer-framework/packer/

# 3. Export the required Packer variables.
export PKR_VAR_aws_region="us-east-1"
export PKR_VAR_deploy_user_name="ec2-user"

# 4. Validate.
cd aws-packer-framework/packer
export ANSIBLE_CONFIG="$(pwd)/../../ansible-framework/ansible.cfg"
ansible-playbook --syntax-check -i localhost, -c local ./rhel-8.yml
packer init .
packer validate .
```

## Build by dispatch

```bash
gh workflow run packer.yaml --repo nwarila-platform/secure-rhel8-ami --ref main
gh run watch "$(gh run list --repo nwarila-platform/secure-rhel8-ami --workflow packer.yaml \
  --limit 1 --json databaseId --jq '.[0].databaseId')" --repo nwarila-platform/secure-rhel8-ami
```

The run summary reports the vulnerability counts, the canary verdict and, when a new image
is published, its AMI ID and change key. Build evidence (RPM manifest and database, SBOM, vulnerability report, OpenSCAP ARF and HTML
report) is attached to the run as the `build-evidence` artifact. The canary's console log is not in
it: the canary writes `evidence/canary-console.log` in the repository directory, and the upload step
collects the framework checkout's `evidence/` directory.

## Cleanup

The workflow terminates the build instance, the canary and their temporary key pair and
security group, and deregisters a candidate that failed the canary. If a run is cancelled
hard, check for orphaned `packer-build-secure-rhel8` or `canary-secure-rhel8` instances and
`packer_*` or `canary-secure-rhel8-*` security groups in the build region.

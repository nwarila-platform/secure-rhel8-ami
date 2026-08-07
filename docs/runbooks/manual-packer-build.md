# Manual Packer Build

Run a build from a workstation when CI is unavailable or when iterating on the
inventory. The flow mirrors the `Packer Build (AWS)` workflow exactly: consumer
files are synced into a SHA-pinned framework checkout and Packer runs from the
framework's `packer/` working directory.

## Prerequisites

- Packer 1.15.0
- ansible-core with `ansible-playbook` on PATH
- AWS credentials in the ambient chain (SSO profile, assumed role) with the
  Packer EC2/EBS/AMI permission baseline
- Git access to `nwarila-platform/aws-packer-framework` and
  `nwarila-platform/ansible-framework`

## Steps

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

# 4. Validate and build.
cd aws-packer-framework/packer
export ANSIBLE_CONFIG="$(pwd)/../../ansible-framework/ansible.cfg"
packer init .
packer validate .
packer build -timestamp-ui .
```

## Cleanup

Packer terminates the build instance and deletes the temporary keypair and
security group automatically, including on most failure paths. If a build is
killed hard, check for orphaned `packer-build-secure-rhel8` instances and
`packer_*` security groups in the build region.

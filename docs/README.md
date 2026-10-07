# Documentation

This repo follows the Diataxis documentation layout:

- `explanation/` - the STIG/CIS hardening strategy and its known limits.
- `reference/` - the AWS IAM the build assumes.
- `runbooks/` - operational guides (validate locally, build by dispatch).

The shared Packer template lives under [`../packer/`](../packer/) and each image's inputs
under `../images/<image>/`. The variable contract the template implements is documented in
[aws-packer-framework](https://github.com/nwarila-platform/aws-packer-framework/tree/main/docs),
from which the template was folded in.

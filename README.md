# REUSABLE EFS Module

A reusable Terraform module that creates an encrypted EFS file system with a mount target in each subnet, a security group for NFS (port 2049), access points and optional backups, driven entirely by variables.

## Design principles

- **Nothing is hardcoded.** Subnets, access point paths and users all come in through variables.
- **Secure by default.** Encrypted at rest, TLS enforced in transit, backups on.
- **`for_each` over one-off resources.** Mount targets and access points are built from maps, so adding one is one more entry.
- **Validation catches mistakes before `apply`.** Bad paths, permissions, throughput and KMS settings fail at `plan`.

## Variables

| Variable | Type | Default | Description |
| --- | --- | --- | --- |
| `team` | string | required | Lowercase team name, used in names and tags (max 20 characters) |
| `environment` | string | required | `"dev"` or `"prod"` |
| `vpc_id` | string | required | VPC the file system lives in |
| `subnet_ids` | map(string) | required | Subnets that get a mount target, keyed by name. One per availability zone |
| `allowed_security_group_ids` | list(string) | `[]` | Security groups allowed to mount (normally the ECS service security groups) |
| `allowed_cidr_blocks` | list(string) | `[]` | CIDR ranges allowed to mount |
| `encrypted` | bool | `true` | Encryption at rest |
| `kms_key_arn` | string | `null` | Your own KMS key, otherwise the AWS managed EFS key |
| `performance_mode` | string | `"generalPurpose"` | `"generalPurpose"` or `"maxIO"` |
| `throughput_mode` | string | `"bursting"` | `"bursting"`, `"elastic"` or `"provisioned"` |
| `provisioned_throughput_in_mibps` | number | `null` | Required for `"provisioned"` |
| `transition_to_ia` | string | `null` | e.g. `"AFTER_30_DAYS"` moves cold files to cheaper storage |
| `enable_backup` | bool | `true` | Automatic backups |
| `enforce_tls` | bool | `true` | File system policy that refuses unencrypted connections |
| `access_points` | map(object) | `{}` | Keyed by name, each with `path` and optional `posix_uid`, `posix_gid`, `permissions` |

```hcl
access_points = {
  data = { path = "/data" }
}
```

## How it connects to ECS

- Pass `module.Networking.private_subnet_ids` (or the public map) as `subnet_ids`.
- Pass the ECS service security group IDs as `allowed_security_group_ids`.
- In the ECS module, give each volume `file_system_id = module.EFS.file_system_id` and `access_point_id = module.EFS.access_point_ids["data"]`.
- Give the task role `elasticfilesystem:ClientMount` and `elasticfilesystem:ClientWrite` on `module.EFS.file_system_arn`. With `enforce_tls = true` the file system policy has no allow statement, so this IAM permission is what lets the task in.

## Notes

- Do not use `depends_on` on the module blocks when two modules reference each other (EFS needs the ECS security group, ECS needs the EFS ids). Plain output references are enough and Terraform resolves the order.
- SQLite works on EFS when only one task writes at a time. Make sure two scheduled runs can never overlap.

## Outputs

| Output | Description |
| --- | --- |
| `file_system_id` | File system ID |
| `file_system_arn` | File system ARN |
| `file_system_dns_name` | DNS name |
| `security_group_id` | Security group guarding the file system |
| `mount_target_ids` | Map of subnet name, mount target ID |
| `access_point_ids` | Map of name, access point ID |
| `access_point_arns` | Map of name, access point ARN |

## Using this module

```hcl
module "efs" {
  source = "git::https://github.com/KateChukwusom/AWSTerraform_Modules.git//modules/EFS?ref=v1.0.0"

  team                       = "platform"
  environment                = "dev"
  vpc_id                     = module.networking.vpc_id
  subnet_ids                 = module.networking.private_subnet_ids
  allowed_security_group_ids = values(module.ecs.service_security_group_ids)
  access_points              = { data = { path = "/data" } }
}
```

## Requirements

Terraform >= 1.9.0 and the AWS provider ~> 6.0.

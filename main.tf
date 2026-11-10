locals {
  # This is the base combination, reused everywhere
  team_environment = "${var.team}-${var.environment}"

  # tags applied to resource blocks that allows tags argument
  resource_tags = {
    Team        = var.team
    Environment = var.environment
  }

  # Security group rules keyed by list index, not by id, because the ids often come from other modules
  # and are not known until apply, and for_each keys must be known at plan time
  ingress_from_security_groups = { for idx, sg_id in var.allowed_security_group_ids : tostring(idx) => sg_id }
  ingress_from_cidrs           = { for idx, cidr in var.allowed_cidr_blocks : tostring(idx) => cidr }
}

#This creates the EFS file system, the persistent storage that outlives your containers
resource "aws_efs_file_system" "cob_efs" {
  creation_token   = "${local.team_environment}-efs"
  encrypted        = var.encrypted
  kms_key_id       = var.kms_key_arn
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode

  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  # Moves files that have not been read for a while to the cheaper infrequent access storage class
  dynamic "lifecycle_policy" {
    for_each = var.transition_to_ia == null ? [] : [var.transition_to_ia]
    content {
      transition_to_ia = lifecycle_policy.value
    }
  }

  tags = merge(local.resource_tags, { Name = "${local.team_environment}-efs" })
}

#This creates the security group that guards the file system, NFS uses port 2049
resource "aws_security_group" "cob_efs_sg" {
  name        = "${local.team_environment}-efs-sg"
  description = "NFS access to the ${local.team_environment} EFS file system"
  vpc_id      = var.vpc_id

  tags = merge(local.resource_tags, { Name = "${local.team_environment}-efs-sg" })
}

#This allows NFS from other security groups, normally the ECS service security groups
resource "aws_vpc_security_group_ingress_rule" "cob_nfs_from_sg" {
  for_each = local.ingress_from_security_groups

  security_group_id            = aws_security_group.cob_efs_sg.id
  referenced_security_group_id = each.value
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
}

#This allows NFS from CIDR ranges
resource "aws_vpc_security_group_ingress_rule" "cob_nfs_from_cidr" {
  for_each = local.ingress_from_cidrs

  security_group_id = aws_security_group.cob_efs_sg.id
  cidr_ipv4         = each.value
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
}

#This creates a mount target in each subnet, this is the network address (a private IP) clients connect to
resource "aws_efs_mount_target" "cob_mount" {
  for_each = var.subnet_ids

  file_system_id  = aws_efs_file_system.cob_efs.id
  subnet_id       = each.value
  security_groups = [aws_security_group.cob_efs_sg.id]
}

#This creates the access points, each one pins clients to a directory and a user so the container cannot wander
resource "aws_efs_access_point" "cob_access_point" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.cob_efs.id

  posix_user {
    uid = each.value.posix_uid
    gid = each.value.posix_gid
  }

  root_directory {
    path = each.value.path

    creation_info {
      owner_uid   = each.value.posix_uid
      owner_gid   = each.value.posix_gid
      permissions = each.value.permissions
    }
  }

  tags = merge(local.resource_tags, { Name = "${local.team_environment}-${each.key}" })

  depends_on = [aws_efs_mount_target.cob_mount]
}

#This creates the json document that refuses any connection that is not encrypted in transit
data "aws_iam_policy_document" "cob_efs_policy" {
  count = var.enforce_tls ? 1 : 0

  statement {
    sid       = "DenyNonTLS"
    effect    = "Deny"
    actions   = ["*"]
    resources = [aws_efs_file_system.cob_efs.arn]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

#This attaches the policy to the file system. With a policy in place, clients need an IAM permission (ClientMount / ClientWrite) to use it
resource "aws_efs_file_system_policy" "cob_policy" {
  count = var.enforce_tls ? 1 : 0

  file_system_id = aws_efs_file_system.cob_efs.id
  policy         = data.aws_iam_policy_document.cob_efs_policy[0].json
}

#This turns on automatic backups of the file system
resource "aws_efs_backup_policy" "cob_backup" {
  count = var.enable_backup ? 1 : 0

  file_system_id = aws_efs_file_system.cob_efs.id

  backup_policy {
    status = "ENABLED"
  }
}
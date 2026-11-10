#The name of the team
variable "team" {
  type        = string
  description = "The team that owns the file system, used in resource names and tags"
  validation {
    condition     = length(var.team) <= 20
    error_message = "team must be 20 characters or fewer"
  }
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.team))
    error_message = "team must be lowercase letters, digits or hyphens only (ECR repository names must be lowercase)"
  }
}

#Deployment environment
variable "environment" {
  type        = string
  description = "Current environment"
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be dev or prod, it must be spelt that way"
  }
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the file system lives in, normally the vpc_id output of the Networking module"
}

# Subnets that get a mount target, keyed by name. Pass a map output of the Networking module directly:
# subnet_ids = module.Networking.private_subnet_ids
# Use at most one subnet per availability zone, EFS allows one mount target per AZ.
variable "subnet_ids" {
  type        = map(string)
  description = "Subnets that get a mount target, keyed by name. One subnet per availability zone at most"
  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "Provide at least one subnet."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to mount the file system (NFS port 2049), normally the ECS service security groups"
  default     = []
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "CIDR ranges allowed to mount the file system (NFS port 2049)"
  default     = []
  validation {
    condition     = alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "Every entry in allowed_cidr_blocks must be a valid CIDR block."
  }
}

variable "encrypted" {
  type        = bool
  description = "Encrypt the file system at rest"
  default     = true
}

variable "kms_key_arn" {
  type        = string
  description = "KMS key used for encryption at rest. Leave null to use the AWS managed EFS key"
  default     = null
  validation {
    condition     = var.kms_key_arn == null || var.encrypted
    error_message = "kms_key_arn can only be set when encrypted is true."
  }
}

variable "performance_mode" {
  type        = string
  description = "generalPurpose suits almost every workload, maxIO is for highly parallel workloads"
  default     = "generalPurpose"
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "performance_mode must be \"generalPurpose\" or \"maxIO\"."
  }
}

variable "throughput_mode" {
  type        = string
  description = "bursting, elastic or provisioned"
  default     = "bursting"
  validation {
    condition     = contains(["bursting", "elastic", "provisioned"], var.throughput_mode)
    error_message = "throughput_mode must be \"bursting\", \"elastic\" or \"provisioned\"."
  }
}

variable "provisioned_throughput_in_mibps" {
  type        = number
  description = "Throughput in MiB/s, required when throughput_mode is provisioned"
  default     = null
  validation {
    condition     = var.throughput_mode != "provisioned" || var.provisioned_throughput_in_mibps != null
    error_message = "provisioned_throughput_in_mibps is required when throughput_mode is \"provisioned\"."
  }
}

variable "transition_to_ia" {
  type        = string
  description = "Move files not read for this long to the infrequent access class, e.g. AFTER_30_DAYS. Null turns it off"
  default     = null
  validation {
    condition = var.transition_to_ia == null ? true : contains(
      ["AFTER_1_DAY", "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", "AFTER_60_DAYS", "AFTER_90_DAYS", "AFTER_180_DAYS", "AFTER_270_DAYS", "AFTER_365_DAYS"],
      var.transition_to_ia
    )
    error_message = "transition_to_ia must be null or one of AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, AFTER_180_DAYS, AFTER_270_DAYS, AFTER_365_DAYS."
  }
}

variable "enable_backup" {
  type        = bool
  description = "Turn on automatic backups with AWS Backup"
  default     = true
}

variable "enforce_tls" {
  type        = bool
  description = "Attach a file system policy that refuses connections that are not encrypted in transit"
  default     = true
}

# Access points, keyed by name. Each one pins clients to a directory and a user. This is what it should look like:

# access_points = {
#   data = { path = "/data" }
#   logs = { path = "/logs", posix_uid = 1001, posix_gid = 1001, permissions = "0755" }
# }
variable "access_points" {
  type = map(object({
    path        = string
    posix_uid   = optional(number, 1000)
    posix_gid   = optional(number, 1000)
    permissions = optional(string, "0750")
  }))
  description = "Access points keyed by name, each with its directory path and the user it acts as"
  default     = {}

  validation {
    condition     = alltrue([for key, ap in var.access_points : can(regex("^[A-Za-z0-9_-]+$", key))])
    error_message = "Access point keys may only contain letters, digits, hyphens and underscores."
  }

  validation {
    condition     = alltrue([for key, ap in var.access_points : startswith(ap.path, "/") && ap.path != "/"])
    error_message = "Every access point path must start with / and cannot be the root / itself."
  }

  validation {
    condition     = alltrue([for key, ap in var.access_points : can(regex("^[0-7]{3,4}$", ap.permissions))])
    error_message = "permissions must be an octal string such as \"0750\"."
  }
}
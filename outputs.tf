# outputs.tf

output "file_system_id" {
  description = "ID of the file system, used as file_system_id in the ECS volume"
  value       = aws_efs_file_system.cob_efs.id
}

output "file_system_arn" {
  description = "ARN of the file system, used in the task role's ClientMount and ClientWrite permissions"
  value       = aws_efs_file_system.cob_efs.arn
}

output "file_system_dns_name" {
  description = "DNS name of the file system"
  value       = aws_efs_file_system.cob_efs.dns_name
}

output "security_group_id" {
  description = "ID of the security group guarding the file system"
  value       = aws_security_group.cob_efs_sg.id
}

output "mount_target_ids" {
  description = "IDs of the mount targets, keyed by subnet name"
  value       = { for key, mt in aws_efs_mount_target.cob_mount : key => mt.id }
}

output "access_point_ids" {
  description = "IDs of the access points, keyed by access point name, used as access_point_id in the ECS volume"
  value       = { for key, ap in aws_efs_access_point.cob_access_point : key => ap.id }
}

output "access_point_arns" {
  description = "ARNs of the access points, keyed by access point name"
  value       = { for key, ap in aws_efs_access_point.cob_access_point : key => ap.arn }
}
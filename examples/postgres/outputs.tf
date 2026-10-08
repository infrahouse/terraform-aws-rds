output "endpoint" {
  description = "RDS connection endpoint"
  value       = module.rds.db_instance_endpoint
}

output "secret_arn" {
  description = "ARN of the master password secret"
  value       = module.rds.master_secret_arn
}

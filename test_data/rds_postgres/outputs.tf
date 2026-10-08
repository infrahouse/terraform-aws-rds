output "db_instance_id" {
  value = module.rds.db_instance_id
}

output "db_instance_arn" {
  value = module.rds.db_instance_arn
}

output "db_instance_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "db_instance_address" {
  value = module.rds.db_instance_address
}

output "db_instance_port" {
  value = module.rds.db_instance_port
}

output "db_instance_name" {
  value = module.rds.db_instance_name
}

output "db_instance_username" {
  value = module.rds.db_instance_username
}

output "master_secret_arn" {
  value = module.rds.master_secret_arn
}

output "security_group_id" {
  value = module.rds.security_group_id
}

output "db_subnet_group_name" {
  value = module.rds.db_subnet_group_name
}

output "parameter_group_name" {
  value = module.rds.parameter_group_name
}

output "dashboard_name" {
  value = module.rds.dashboard_name
}

data "aws_region" "current" {}

data "aws_subnet" "first" {
  id = var.subnet_ids[0]
}

data "aws_vpc" "this" {
  id = data.aws_subnet.first.vpc_id
}

data "aws_ec2_instance_type" "this" {
  instance_type = local.ec2_instance_type
}

locals {
  module_version = "0.1.0"

  # db.t4g.micro -> t4g.micro
  ec2_instance_type = replace(var.instance_class, "/^db\\./", "")

  # engine_version "8.4" -> "mysql8.4", "8.0" -> "mysql8.0"
  parameter_group_family = (
    var.parameter_group_family != null
    ? var.parameter_group_family
    : "mysql${var.engine_version}"
  )

  # Memory calculations
  total_memory_bytes     = data.aws_ec2_instance_type.this.memory_size * 1024 * 1024
  memory_threshold_bytes = local.total_memory_bytes * var.alarm_memory_percent / 100

  # Storage thresholds (bytes)
  allocated_storage_bytes  = var.allocated_storage * 1024 * 1024 * 1024
  storage_threshold_normal = local.allocated_storage_bytes * var.alarm_storage_percent_normal / 100
  storage_threshold_high   = local.allocated_storage_bytes * var.alarm_storage_percent_high / 100
  storage_threshold_urgent = local.allocated_storage_bytes * var.alarm_storage_percent_urgent / 100

  # Connections threshold
  default_max_connections = floor(local.total_memory_bytes / 12582880)
  connections_threshold = (
    var.alarm_connections_threshold != null
    ? var.alarm_connections_threshold
    : floor(local.default_max_connections * 0.8)
  )

  # VPC CIDR for default security group rules
  vpc_cidr      = data.aws_vpc.this.cidr_block
  allowed_cidrs = var.allowed_cidrs != null ? var.allowed_cidrs : [local.vpc_cidr]

  # Identifier
  identifier_prefix = var.identifier_prefix != null ? var.identifier_prefix : "${var.service_name}-"

  # Vanta tags
  vanta_owner    = var.vanta_owner != null ? var.vanta_owner : var.service_name
  vanta_non_prod = var.vanta_non_prod != null ? var.vanta_non_prod : !contains(["production", "prod"], var.environment)

  vanta_tags = {
    VantaOwner            = local.vanta_owner
    VantaNonProd          = tostring(local.vanta_non_prod)
    VantaContainsUserData = tostring(var.vanta_contains_user_data)
    VantaContainsEPHI     = tostring(var.vanta_contains_ephi)
    VantaDescription      = var.vanta_description
    VantaUserDataStored   = var.vanta_user_data_stored != null ? var.vanta_user_data_stored : ""
  }

  default_module_tags = merge(
    {
      environment       = var.environment
      service           = var.service_name
      created_by_module = "infrahouse/rds/aws"
    },
    local.vanta_tags,
    var.tags
  )

  # Alarm notification targets
  default_sns_arn      = local.create_sns_topic ? aws_sns_topic.alarms[0].arn : null
  alarm_actions_urgent = [coalesce(var.notifications.urgent, local.default_sns_arn)]
  alarm_actions_high   = [coalesce(var.notifications.high, local.default_sns_arn)]
  alarm_actions_normal = [coalesce(var.notifications.normal, local.default_sns_arn)]
}

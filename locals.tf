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
  module_version = "0.2.2"

  # db.t4g.micro -> t4g.micro
  ec2_instance_type = replace(var.instance_class, "/^db\\./", "")

  # Everything that differs between engines lives here; the rest of the module reads local.engine_config.
  engine_configs = {
    mysql = {
      display_name    = "MySQL"
      default_version = "8.4"
      default_port    = 3306
      default_user    = "admin"
      logs_exports    = ["error", "slowquery"]
      # Families track major.minor: "8.4.3" -> "mysql8.4"
      family_prefix        = "mysql"
      family_version_parts = 2
      # RDS default max_connections = DBInstanceClassMemory / 12582880
      max_connections = floor(local.total_memory_bytes / 12582880)
      parameters = [
        { name = "log_bin_trust_function_creators", value = "1", apply_method = "immediate" },
        { name = "binlog_format", value = "ROW", apply_method = "immediate" },
        { name = "performance_schema", value = "1", apply_method = "pending-reboot" },
        { name = "read_only", value = var.read_only ? "1" : "0", apply_method = "immediate" },
        { name = "long_query_time", value = tostring(var.long_query_time), apply_method = "immediate" },
      ]
    }
    postgres = {
      display_name    = "PostgreSQL"
      default_version = "18"
      default_port    = 5432
      # "admin" is reserved by RDS for PostgreSQL
      default_user = "postgres"
      logs_exports = ["postgresql", "upgrade"]
      # Families track the major version: "18.6" -> "postgres18"
      family_prefix        = "postgres"
      family_version_parts = 1
      # RDS default max_connections = LEAST(DBInstanceClassMemory / 9531392, 5000)
      max_connections = min(floor(local.total_memory_bytes / 9531392), 5000)
      # rds.force_ssl = 1 and shared_preload_libraries = pg_stat_statements,pg_tle are already
      # postgres18 engine defaults, so only slow-query logging is set here.
      parameters = [
        {
          name         = "log_min_duration_statement"
          value        = tostring(floor(var.long_query_time * 1000))
          apply_method = "immediate"
        },
      ]
    }
  }
  engine_config = local.engine_configs[var.engine]

  engine_version = var.engine_version != null ? var.engine_version : local.engine_config.default_version
  port           = var.port != null ? var.port : local.engine_config.default_port
  username       = var.username != null ? var.username : local.engine_config.default_user

  # "8.4.3" -> "8.4" for mysql, "18.6" -> "18" for postgres
  engine_version_parts = split(".", local.engine_version)
  family_version = join(".", slice(
    local.engine_version_parts, 0, min(local.engine_config.family_version_parts, length(local.engine_version_parts))
  ))
  parameter_group_family = (
    var.parameter_group_family != null
    ? var.parameter_group_family
    : "${local.engine_config.family_prefix}${local.family_version}"
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
  default_max_connections = local.engine_config.max_connections
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

  vanta_description = (
    var.vanta_description != null ? var.vanta_description : "RDS ${local.engine_config.display_name} database"
  )

  vanta_tags = {
    VantaOwner            = local.vanta_owner
    VantaNonProd          = tostring(local.vanta_non_prod)
    VantaContainsUserData = tostring(var.vanta_contains_user_data)
    VantaContainsEPHI     = tostring(var.vanta_contains_ephi)
    VantaDescription      = local.vanta_description
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
  alarm_actions_urgent = [local.create_sns_topic ? aws_sns_topic.alarms[0].arn : var.notifications.urgent]
  alarm_actions_high   = [local.create_sns_topic ? aws_sns_topic.alarms[0].arn : var.notifications.high]
  alarm_actions_normal = [local.create_sns_topic ? aws_sns_topic.alarms[0].arn : var.notifications.normal]
}

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.service_name}-"
  subnet_ids  = var.subnet_ids

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.service_name}-"
  family      = local.parameter_group_family

  parameter {
    name         = "log_bin_trust_function_creators"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "immediate"
  }

  parameter {
    name         = "performance_schema"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "read_only"
    value        = var.read_only ? "1" : "0"
    apply_method = "immediate"
  }

  parameter {
    name         = "long_query_time"
    value        = tostring(var.long_query_time)
    apply_method = "immediate"
  }

  parameter {
    name         = "server_audit_logging"
    value        = var.server_audit_events != "" ? "1" : "0"
    apply_method = "immediate"
  }

  parameter {
    name         = "server_audit_events"
    value        = var.server_audit_events
    apply_method = "immediate"
  }

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = "immediate"
    }
  }

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-parameter-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier_prefix = local.identifier_prefix

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  db_name  = var.db_name
  username = var.username
  port     = var.port

  manage_master_user_password         = true
  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  parameter_group_name   = aws_db_parameter_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.service_name}-final-snapshot"
  apply_immediately         = var.apply_immediately

  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(local.default_module_tags, {
    Name           = var.service_name
    module_version = local.module_version
  })
}

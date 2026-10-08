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

  dynamic "parameter" {
    for_each = local.engine_config.parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
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

    precondition {
      condition     = var.engine == "postgres" ? !var.read_only : true
      error_message = <<-EOT
        read_only = true is not supported with engine = "postgres". PostgreSQL has no server-wide
        read-only switch: default_transaction_read_only is only a session default that any client can
        override with SET. Revoke write privileges or use a read replica instead.
      EOT
    }
  }
}

resource "aws_db_instance" "this" {
  identifier_prefix = local.identifier_prefix

  engine         = var.engine
  engine_version = local.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  db_name  = var.db_name
  username = local.username
  port     = local.port

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

  enabled_cloudwatch_logs_exports = local.engine_config.logs_exports

  performance_insights_enabled          = true
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(local.default_module_tags, {
    Name           = var.service_name
    module_version = local.module_version
  })
}

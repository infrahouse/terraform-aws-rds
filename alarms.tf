resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = "${var.service_name}-${var.environment}-cpu-utilization"
  alarm_description   = "RDS CPU utilization above ${var.alarm_cpu_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_cpu_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = var.alarm_cpu_period
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_high
  ok_actions    = local.alarm_actions_high

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "freeable_memory" {
  alarm_name          = "${var.service_name}-${var.environment}-freeable-memory"
  alarm_description   = "RDS freeable memory below ${var.alarm_memory_percent}% of total"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_memory_evaluation_periods
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = var.alarm_memory_period
  statistic           = "Average"
  threshold           = local.memory_threshold_bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_high
  ok_actions    = local.alarm_actions_high

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_normal" {
  alarm_name          = "${var.service_name}-${var.environment}-free-storage-normal"
  alarm_description   = "RDS free storage below ${var.alarm_storage_percent_normal}%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_storage_evaluation_periods
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = var.alarm_storage_period
  statistic           = "Average"
  threshold           = local.storage_threshold_normal
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_normal
  ok_actions    = local.alarm_actions_normal

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_high" {
  alarm_name          = "${var.service_name}-${var.environment}-free-storage-high"
  alarm_description   = "RDS free storage below ${var.alarm_storage_percent_high}%"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_storage_evaluation_periods
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = var.alarm_storage_period
  statistic           = "Average"
  threshold           = local.storage_threshold_high
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_high
  ok_actions    = local.alarm_actions_high

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "free_storage_urgent" {
  alarm_name          = "${var.service_name}-${var.environment}-free-storage-urgent"
  alarm_description   = "RDS free storage below ${var.alarm_storage_percent_urgent}% — imminent outage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_storage_evaluation_periods
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = var.alarm_storage_period
  statistic           = "Average"
  threshold           = local.storage_threshold_urgent
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_urgent
  ok_actions    = local.alarm_actions_urgent

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "disk_queue_depth" {
  alarm_name          = "${var.service_name}-${var.environment}-disk-queue-depth"
  alarm_description   = "RDS disk queue depth above ${var.alarm_disk_queue_depth_threshold}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_disk_queue_evaluation_periods
  metric_name         = "DiskQueueDepth"
  namespace           = "AWS/RDS"
  period              = var.alarm_disk_queue_period
  statistic           = "Average"
  threshold           = var.alarm_disk_queue_depth_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_normal
  ok_actions    = local.alarm_actions_normal

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  alarm_name          = "${var.service_name}-${var.environment}-database-connections"
  alarm_description   = "RDS database connections above ${local.connections_threshold}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_connections_evaluation_periods
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = var.alarm_connections_period
  statistic           = "Average"
  threshold           = local.connections_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.identifier
  }

  alarm_actions = local.alarm_actions_high
  ok_actions    = local.alarm_actions_high

  tags = local.default_module_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  alarm_name          = local.alarm_names["cpu-utilization"]
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
  alarm_name          = local.alarm_names["freeable-memory"]
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
  alarm_name          = local.alarm_names["free-storage-normal"]
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
  alarm_name          = local.alarm_names["free-storage-high"]
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
  alarm_name          = local.alarm_names["free-storage-urgent"]
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
  alarm_name          = local.alarm_names["disk-queue-depth"]
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
  alarm_name          = local.alarm_names["database-connections"]
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

# ── PostgreSQL's lock table (IH-169) ──────────────────────────────────────
# PostgreSQL keeps table and advisory locks in one shared lock table, about max_locks_per_transaction × max_connections
# entries for the whole server. A transaction that takes more fills it, and every session that then needs a lock fails
# with "out of shared memory" (SQLSTATE 53200) until that transaction ends. No RDS or Performance Insights metric
# reports how full the table is, so the alarm counts the error in PostgreSQL's log.

# RDS creates the group itself when it first exports a line, which it does while it creates the instance, minutes
# before the instance is available. The module reads the group instead of creating it: for an existing instance it
# already exists and can't be imported from a module, and RDS's group keeps its retention.
data "aws_cloudwatch_log_group" "postgresql" {
  count = var.engine == "postgres" ? 1 : 0
  name  = "/aws/rds/instance/${aws_db_instance.this.identifier}/postgresql"
}

locals {
  # PostgreSQL logs the error, then a HINT and a STATEMENT line, each one event. "]:" ends the line's prefix,
  # %t:%r:%u@%d:[%p]:, so the pattern matches the error line once, whatever the statement says. A session that can't
  # take a lock while it connects fails with FATAL instead of ERROR.
  out_of_shared_memory_pattern = join(" ", [
    for severity in ["ERROR", "FATAL"] : "?\"]:${severity}:  out of shared memory\""
  ])
}

resource "aws_cloudwatch_log_metric_filter" "out_of_shared_memory" {
  count = var.engine == "postgres" ? 1 : 0

  name           = local.alarm_names["out-of-shared-memory"]
  log_group_name = data.aws_cloudwatch_log_group.postgresql[0].name
  pattern        = local.out_of_shared_memory_pattern

  # No default value: a quiet log publishes nothing, and the alarm reads the gap as not breaching.
  metric_transformation {
    namespace = "InfraHouse/RDS"
    name      = local.alarm_names["out-of-shared-memory"]
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "out_of_shared_memory" {
  count = var.engine == "postgres" ? 1 : 0

  alarm_name = local.alarm_names["out-of-shared-memory"]
  alarm_description = join(" ", [
    "PostgreSQL answered \"out of shared memory\" (SQLSTATE 53200): its lock table was full. The table holds about",
    "max_locks_per_transaction × max_connections table and advisory locks for the whole server; a transaction that",
    "takes more, such as one advisory lock per row, fails every session that needs a lock until it ends. Row locks",
    "don't count, PostgreSQL keeps them in the rows. Find the sessions in PostgreSQL's log,",
    "${data.aws_cloudwatch_log_group.postgresql[0].name}, on the lines with \"out of shared memory\" and the",
    "STATEMENT line after each. While the table is full, pg_locks shows who holds the locks:",
    "SELECT pid, locktype, count(*) FROM pg_locks GROUP BY 1, 2 ORDER BY 3 DESC.",
  ])
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.out_of_shared_memory[0].metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.out_of_shared_memory[0].metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  # High, as CPU's: queries fail while the table is full, and it empties on its own when the transaction ends.
  alarm_actions = local.alarm_actions_high
  ok_actions    = local.alarm_actions_high

  tags = local.default_module_tags
}

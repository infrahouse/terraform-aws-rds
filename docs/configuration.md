# Configuration

## Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `environment` | `string` | Environment name (lowercase, underscores only) |
| `service_name` | `string` | Service name (used in naming and tags) |
| `subnet_ids` | `list(string)` | Private subnet IDs (minimum 2 for Multi-AZ) |
| `alarm_emails` | `list(string)` | Email addresses for alarm notifications (minimum 1) |

## Instance Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `engine` | `mysql` | Database engine: `mysql` or `postgres` |
| `instance_class` | `db.t4g.medium` | RDS instance class (must support Performance Insights) |
| `engine_version` | `null` | `8.4` for mysql, `18` for postgres (a major version picks the latest minor) |
| `allocated_storage` | `20` | Initial storage in GiB |
| `max_allocated_storage` | `100` | Max storage for autoscaling in GiB |
| `storage_type` | `gp3` | Storage type (gp3, io1, io2) |
| `multi_az` | `true` | Enable Multi-AZ deployment |
| `port` | `null` | `3306` for mysql, `5432` for postgres |
| `db_name` | `null` | Database name to create (null = no database) |
| `username` | `null` | `admin` for mysql, `postgres` for postgres |

## Operational Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `apply_immediately` | `true` | Apply changes immediately vs. maintenance window |
| `deletion_protection` | `true` | Prevent accidental deletion |
| `skip_final_snapshot` | `false` | Skip final snapshot on deletion |
| `backup_retention_period` | `7` | Days to retain automated backups |
| `backup_window` | `02:00-02:30` | Preferred backup window (UTC) |
| `maintenance_window` | `Mon:03:00-Mon:04:00` | Preferred maintenance window (UTC) |
| `read_only` | `false` | Set the database to read-only mode (MySQL only, see below) |
| `performance_insights_retention_period` | `7` | PI retention in days (7 = free tier) |

## Parameter Group

| Variable | Default | Description |
|----------|---------|-------------|
| `parameter_group_family` | `null` | Auto-derived from engine and engine_version (`mysql8.4`, `postgres18`) |
| `long_query_time` | `1` | Slow query threshold in seconds (both engines) |
| `parameters` | `[]` | Additional DB parameters to set |

Parameters the module sets:

| Engine | Parameter | Value |
|--------|-----------|-------|
| mysql | `log_bin_trust_function_creators` | `1` |
| mysql | `binlog_format` | `ROW` |
| mysql | `performance_schema` | `1` (pending reboot) |
| mysql | `read_only` | `1` if `read_only = true`, else `0` |
| mysql | `long_query_time` | `long_query_time` |
| postgres | `log_min_duration_statement` | `long_query_time` × 1000 (milliseconds) |

On PostgreSQL, TLS is already required (`rds.force_ssl = 1`) and `pg_stat_statements` is already in
`shared_preload_libraries` by RDS default for `postgres18`, so the module doesn't set them.

`read_only = true` is rejected when `engine = "postgres"`. PostgreSQL has no server-wide read-only switch:
`default_transaction_read_only` only sets the session default, and any client can turn it off with `SET`.
Revoke write privileges or use a read replica instead.

Example of custom parameters (MySQL):

```hcl
parameters = [
  { name = "max_connections", value = "500" },
  { name = "innodb_buffer_pool_size", value = "{DBInstanceClassMemory*3/4}" },
]
```

Example of custom parameters (PostgreSQL):

```hcl
parameters = [
  { name = "work_mem", value = "16384" },
  { name = "idle_in_transaction_session_timeout", value = "600000" },
]
```

Additional parameters are applied with `apply_method = "immediate"`, so use them for dynamic parameters only.

## Notifications

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_emails` | (required) | Email addresses for notifications |
| `notifications` | `{}` | SNS topic ARNs per severity (overrides auto-created topic) |

When `notifications` is empty (default), the module creates an SNS topic and subscribes
all `alarm_emails`. When `notifications` is set, the provided ARNs are used directly.

```hcl
# Advanced: route urgent to PagerDuty, normal to email
notifications = {
  urgent = aws_sns_topic.pagerduty.arn
  high   = aws_sns_topic.pagerduty.arn
  normal = aws_sns_topic.email.arn
}
```

## Alarm Thresholds

### CPU

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_cpu_threshold` | `80` | CPU utilization % |
| `alarm_cpu_evaluation_periods` | `2` | Evaluation periods |
| `alarm_cpu_period` | `300` | Period in seconds |

### Memory

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_memory_percent` | `5` | Freeable memory as % of total |
| `alarm_memory_evaluation_periods` | `2` | Evaluation periods |
| `alarm_memory_period` | `900` | Period in seconds |

### Storage (three severity tiers)

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_storage_percent_normal` | `20` | Free storage % for normal alarm |
| `alarm_storage_percent_high` | `10` | Free storage % for high alarm |
| `alarm_storage_percent_urgent` | `5` | Free storage % for urgent alarm |
| `alarm_storage_evaluation_periods` | `1` | Evaluation periods |
| `alarm_storage_period` | `300` | Period in seconds |

!!! note "Thresholds are based on `allocated_storage`, not current size"
    Storage alarm thresholds are calculated as a percentage of `allocated_storage`
    (the initial allocation), not the current autoscaled size. For example, with
    `allocated_storage = 20` and `alarm_storage_percent_normal = 20`, the normal
    alarm fires when free storage drops below 4 GiB — even if the volume has
    autoscaled to 50 GiB. This is intentional: if your database has grown well
    beyond its initial allocation, that itself warrants investigation.

### Disk Queue

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_disk_queue_depth_threshold` | `64` | Disk queue depth |
| `alarm_disk_queue_evaluation_periods` | `3` | Evaluation periods |
| `alarm_disk_queue_period` | `300` | Period in seconds |

### Connections

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_connections_threshold` | `null` | Max connections (null = 80% of instance max) |
| `alarm_connections_evaluation_periods` | `2` | Evaluation periods |
| `alarm_connections_period` | `300` | Period in seconds |

## Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `allowed_cidrs` | `null` | CIDR blocks allowed to connect (null = VPC CIDR) |
| `allowed_security_group_ids` | `[]` | Additional security group IDs allowed access |

## Encryption & Secrets

| Variable | Default | Description |
|----------|---------|-------------|
| `kms_key_id` | `null` | KMS key ARN (null = AWS-managed key) |
| `secret_readers` | `[]` | IAM ARNs allowed to read the master password secret |

## Vanta Compliance Tags

| Variable | Default | Description |
|----------|---------|-------------|
| `vanta_owner` | `null` | VantaOwner (defaults to service_name) |
| `vanta_non_prod` | `null` | VantaNonProd (derived from environment) |
| `vanta_contains_user_data` | `true` | VantaContainsUserData |
| `vanta_contains_ephi` | `false` | VantaContainsEPHI |
| `vanta_description` | `null` | `RDS MySQL database` or `RDS PostgreSQL database` |
| `vanta_user_data_stored` | `null` | VantaUserDataStored |

## Outputs

| Output | Description |
|--------|-------------|
| `db_instance_id` | The RDS instance identifier |
| `db_instance_arn` | The RDS instance ARN |
| `db_instance_endpoint` | Connection endpoint (host:port) |
| `db_instance_address` | Hostname |
| `db_instance_port` | Port |
| `db_instance_name` | Database name |
| `db_instance_username` | Master username |
| `master_secret_arn` | Secrets Manager secret ARN |
| `security_group_id` | Security group ID |
| `db_subnet_group_name` | DB subnet group name |
| `parameter_group_name` | Parameter group name |
| `dashboard_name` | CloudWatch dashboard name |

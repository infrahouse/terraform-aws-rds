# Architecture

## How It Works

![Architecture](assets/architecture.svg)

## Design Decisions

### Performance Insights Always On

PI is hardcoded to enabled because:

- The 7-day retention is free on supported instance classes
- It's essential for diagnosing production issues
- The module enforces `db.t4g.medium` minimum (smallest PI-compatible class for MySQL 8.4)

### Severity-Based Alarm Routing

Alarms are categorized by operational impact:

| Severity | Alarms | Default Response |
|----------|--------|-----------------|
| **Urgent** | Storage < 5% | Immediate action required |
| **High** | CPU > 80%, Memory < 5%, Storage < 10%, Connections near max | Investigate within hours |
| **Normal** | Storage < 20%, Disk queue depth | Awareness, plan remediation |

### Auto-Created SNS Topic

When users don't provide explicit SNS topic ARNs, the module creates one topic and subscribes
all `alarm_emails`. This ensures alarms are never silent — a common misconfiguration when
teams set up monitoring but forget to wire up notifications.

### Parameter Group Family Derivation

The parameter group family (e.g., `mysql8.4`) is automatically derived from `engine_version`.
This prevents the common misconfiguration where someone upgrades the engine version but forgets
to update the parameter group family.

### Managed Master Password

The module uses `manage_master_user_password = true`, which means:

- AWS creates and manages the password in Secrets Manager
- The password is never exposed in Terraform state
- Automatic rotation is handled by RDS
- Access to the secret is controlled via `secret_readers` variable

### Storage Encryption

Always enabled (`storage_encrypted = true`). Uses AWS-managed key by default,
or a customer-managed KMS key if `kms_key_id` is provided.

## CloudWatch Dashboard

The dashboard provides PMM-style MySQL monitoring panels:

1. **Header** — QPS, Free Storage, Threads Running, Connections
2. **Connections** — Threads_connected with max_connections line, Aborted connections
3. **Client Threads** — Running vs Connected/Created
4. **Temporary Objects** — tmp_tables vs tmp_disk_tables, Slow queries
5. **Select Types** — full_join, scan, range
6. **Sorts** — rows, merge_passes, scan
7. **Table Locks** — immediate vs waited, Questions & Queries
8. **Network & IOPS** — throughput and read/write IOPS
9. **CPU & Memory** — utilization with alarm thresholds
10. **Disk Queue & Storage** — queue depth and free space with alarm thresholds (in GiB)
11. **InnoDB Row Operations** — rows read/inserted/updated/deleted
12. **InnoDB Transactions** — active transactions and history list length
13. **Buffer Pool & Table Cache** — hit rate, usage, opened tables
14. **Read/Write Latency** — I/O latency

All PI-based widgets use `DB_PERF_INSIGHTS` math expressions, which require the instance
to have Performance Insights enabled.

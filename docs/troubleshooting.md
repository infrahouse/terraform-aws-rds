# Troubleshooting

## Common Issues

### "No data available" on dashboard widgets

**Cause:** Performance Insights counter metrics only populate when there's actual database
activity. An idle instance shows "No data available" for PI-based panels.

**Fix:** Run some queries against the database. The dashboard will populate within 1-2 minutes.

### SNS email subscriptions not receiving alarms

**Cause:** AWS SNS requires email confirmation before delivering notifications.

**Fix:** Check the inbox (and spam folder) of each address in `alarm_emails` for the
AWS SNS confirmation email. Click "Confirm subscription" in each.

### Instance creation fails with "Performance Insights not supported"

**Cause:** The chosen `instance_class` doesn't support Performance Insights for the
selected MySQL version.

**Fix:** Use `db.t4g.medium` or larger for MySQL 8.4. The module defaults to this, but
if you've overridden `instance_class`, ensure your choice supports PI.

Verify support:
```bash
aws rds describe-orderable-db-instance-options \
  --engine mysql \
  --engine-version 8.4 \
  --db-instance-class db.t4g.medium \
  --query "OrderableDBInstanceOptions[*].SupportsPerformanceInsights"
```

### Parameter group changes require reboot

**Cause:** Some parameters (like `performance_schema`) require a reboot to take effect.
The module marks these with `apply_method = "pending-reboot"`.

**Fix:** The change applies at the next maintenance window, or you can trigger a reboot:
```bash
aws rds reboot-db-instance --db-instance-identifier <identifier>
```

### Cannot delete instance — "deletion protection is enabled"

**Cause:** `deletion_protection = true` (the default) prevents accidental deletion.

**Fix:** Set `deletion_protection = false` and apply, then destroy:
```hcl
deletion_protection = false
```

### Security group blocking connections

**Cause:** By default, only the VPC CIDR is allowed. If connecting from outside the VPC
(e.g., a VPN or peered VPC), you need to add the source.

**Fix:** Use `allowed_cidrs` or `allowed_security_group_ids`:
```hcl
allowed_cidrs = ["10.0.0.0/16", "172.16.0.0/12"]

allowed_security_group_ids = [
  module.ecs.security_group_id
]
```

### Storage autoscaling not triggering

**Cause:** RDS autoscaling has built-in cooldowns and only triggers when free storage
falls below 10% of allocated AND the low-storage condition lasts at least 5 minutes AND
at least 6 hours have passed since the last storage modification.

**Fix:** This is expected AWS behavior. If you need more storage immediately, increase
`allocated_storage` and apply.

## Alarm Tuning

### Too many false-positive CPU alarms

Increase the evaluation window:
```hcl
alarm_cpu_threshold          = 90   # from default 80
alarm_cpu_evaluation_periods = 3    # from default 2
alarm_cpu_period             = 600  # from default 300
```

### Storage alarms triggering too early

Adjust the percentage thresholds:
```hcl
alarm_storage_percent_normal = 30  # from default 20
alarm_storage_percent_high   = 15  # from default 10
alarm_storage_percent_urgent = 7   # from default 5
```

### Connection alarm too sensitive

Set an explicit threshold instead of the auto-calculated 80%:
```hcl
alarm_connections_threshold = 200
```

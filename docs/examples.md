# Examples

## Basic — Minimal Configuration

The simplest deployment with all defaults:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  alarm_emails = ["oncall@example.com"]
  db_name      = "myapp"
}
```

## Custom Instance Size

For a larger workload with more storage:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "production"
  service_name = "analytics"
  subnet_ids   = module.vpc.private_subnet_ids

  instance_class        = "db.r6g.xlarge"
  allocated_storage     = 200
  max_allocated_storage = 1000

  alarm_emails = ["dba@example.com"]
  db_name      = "analytics"
}
```

## Custom Notifications — PagerDuty + Email

Route urgent alarms to PagerDuty, normal ones to email:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "production"
  service_name = "payments"
  subnet_ids   = module.vpc.private_subnet_ids

  alarm_emails = ["dba@example.com"]

  notifications = {
    urgent = aws_sns_topic.pagerduty.arn
    high   = aws_sns_topic.pagerduty.arn
    normal = aws_sns_topic.email.arn
  }

  db_name = "payments"
}
```

## Application Access to Secrets

Grant an ECS task role access to read the master password:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "production"
  service_name = "api"
  subnet_ids   = module.vpc.private_subnet_ids

  alarm_emails = ["oncall@example.com"]
  db_name      = "api"

  secret_readers = [
    module.ecs_task.task_role_arn,
    "arn:aws:iam::123456789012:role/admin"
  ]
}
```

## Development Environment

Reduced redundancy and protections for development:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "development"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  multi_az            = false
  deletion_protection = false
  skip_final_snapshot = true

  alarm_emails = ["dev-team@example.com"]
  db_name      = "myapp"
}
```

## MySQL 8.0

Use an older MySQL version:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "production"
  service_name = "legacy-app"
  subnet_ids   = module.vpc.private_subnet_ids

  engine_version = "8.0"

  alarm_emails = ["oncall@example.com"]
  db_name      = "legacy"
}
```

The parameter group family is automatically derived as `mysql8.0`.

## PostgreSQL

PostgreSQL 18 with a 500 ms slow-query threshold:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  engine = "postgres"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  long_query_time = 0.5

  parameters = [
    { name = "work_mem", value = "16384" },
  ]

  alarm_emails = ["oncall@example.com"]
  db_name      = "myapp"
}
```

This creates a PostgreSQL 18 instance (latest 18.x minor) on port 5432 with the master user `postgres`.
The parameter group family is derived as `postgres18`, `log_min_duration_statement` is set to `500`, and the
`postgresql` and `upgrade` logs are exported to CloudWatch. Pin a minor version with `engine_version = "18.6"`.

## Custom Parameters

Tune MySQL for your workload:

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  long_query_time = 2

  parameters = [
    { name = "max_connections", value = "500" },
    { name = "innodb_buffer_pool_size", value = "{DBInstanceClassMemory*3/4}" },
    { name = "innodb_log_buffer_size", value = "67108864" },
  ]

  alarm_emails = ["oncall@example.com"]
  db_name      = "myapp"
}
```

# Getting Started

## Prerequisites

- Terraform >= 1.5
- AWS provider ~> 6.0
- A VPC with at least 2 private subnets in different AZs
- An email address for alarm notifications

## First Deployment

### 1. Basic Configuration

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.2.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = ["subnet-abc123", "subnet-def456"]

  alarm_emails = ["dba@example.com"]
  db_name      = "myapp"
}
```

### 2. Apply

```bash
terraform init
terraform plan
terraform apply
```

### 3. Confirm SNS Subscription

After apply, each email in `alarm_emails` receives a confirmation email from AWS SNS.
Click the confirmation link — until confirmed, alarms won't reach that address.

### 4. Retrieve Connection Details

```bash
# Endpoint
terraform output -raw db_instance_endpoint

# Master password (from Secrets Manager)
aws secretsmanager get-secret-value \
  --secret-id "$(terraform output -raw master_secret_arn)" \
  --query SecretString --output text
```

## What Gets Created

| Resource | Purpose |
|----------|---------|
| `aws_db_instance` | The RDS MySQL instance |
| `aws_db_subnet_group` | Places the instance in your private subnets |
| `aws_db_parameter_group` | MySQL parameters (slow query log, performance_schema, etc.) |
| `aws_security_group` | Network access control |
| `aws_cloudwatch_metric_alarm` (x7) | CPU, memory, storage (3 tiers), disk queue, connections |
| `aws_cloudwatch_dashboard` | PMM-style monitoring dashboard |
| `aws_sns_topic` + subscriptions | Alarm notifications (if not providing your own) |

## Next Steps

- [Configuration Reference](configuration.md) — all variables explained
- [Architecture](architecture.md) — how it works under the hood
- [Examples](examples.md) — common deployment patterns

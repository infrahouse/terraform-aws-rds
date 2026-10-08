# terraform-aws-rds

An opinionated Terraform module for provisioning production-ready AWS RDS MySQL and PostgreSQL instances with
built-in observability, security hardening, and compliance tagging.

## Features

- **MySQL 8.x or PostgreSQL** (`engine = "mysql"` or `"postgres"`) with Performance Insights always enabled
- **7 CloudWatch alarms** with severity-based routing (urgent/high/normal)
- **Per-engine CloudWatch dashboard** with 20+ panels: InnoDB internals, threads, and locks for MySQL;
  transactions, tuples, buffer cache, checkpoints, and transaction ID age for PostgreSQL
- **Automatic SNS notifications** — pass emails and the module handles topic creation;
  or bring your own SNS topic ARNs for advanced routing
- **Storage encryption** (AWS-managed or customer KMS key)
- **Multi-AZ** deployment by default
- **Vanta compliance tags** (SOC2/ISO27001)
- **Secrets Manager** integration with IAM-based reader access control
- **Parameter group family** auto-derived from `engine` and `engine_version` (`mysql8.4`, `postgres18`)

## Quick Start

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.2.2"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  alarm_emails = ["oncall@example.com"]
}
```

For PostgreSQL 18, add `engine = "postgres"`. See [Examples](examples.md#postgresql).

## Architecture

![Architecture](assets/architecture.svg)

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5 |
| AWS provider | ~> 6.0 |

## Instance Classes

Performance Insights is always enabled. For MySQL 8.4 and PostgreSQL 18, the minimum supported
instance class is `db.t4g.medium`. The module defaults to this.

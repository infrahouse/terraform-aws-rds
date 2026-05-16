# terraform-aws-rds

An opinionated Terraform module for provisioning production-ready AWS RDS MySQL instances with
built-in observability, security hardening, and compliance tagging.

## Features

- **MySQL 8.x** with Performance Insights always enabled
- **7 CloudWatch alarms** with severity-based routing (urgent/high/normal)
- **PMM-style CloudWatch dashboard** with 20+ panels covering InnoDB internals,
  connections, locks, buffer pool, temporary objects, and more
- **Automatic SNS notifications** — pass emails and the module handles topic creation;
  or bring your own SNS topic ARNs for advanced routing
- **Storage encryption** (AWS-managed or customer KMS key)
- **Multi-AZ** deployment by default
- **Vanta compliance tags** (SOC2/ISO27001)
- **Secrets Manager** integration with IAM-based reader access control
- **Parameter group family** auto-derived from `engine_version`

## Quick Start

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.2.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  alarm_emails = ["oncall@example.com"]
}
```

## Architecture

![Architecture](assets/architecture.svg)

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5 |
| AWS provider | ~> 6.0 |

## Instance Classes

Performance Insights is always enabled. For MySQL 8.4, the minimum supported instance class
is `db.t4g.medium`. The module defaults to this.

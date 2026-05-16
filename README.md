[![Need Help?](https://img.shields.io/badge/Need%20Help%3F-Contact%20Us-0066CC)](https://infrahouse.com/contact)
[![Docs](https://img.shields.io/badge/docs-github.io-blue)](https://infrahouse.github.io/terraform-aws-rds/)
[![Registry](https://img.shields.io/badge/Terraform-Registry-purple?logo=terraform)](https://registry.terraform.io/modules/infrahouse/rds/aws/latest)
[![Release](https://img.shields.io/github/release/infrahouse/terraform-aws-rds.svg)](https://github.com/infrahouse/terraform-aws-rds/releases/latest)
[![AWS RDS](https://img.shields.io/badge/AWS-RDS-orange?logo=amazonrds)](https://aws.amazon.com/rds/)
[![AWS CloudWatch](https://img.shields.io/badge/AWS-CloudWatch-orange?logo=amazoncloudwatch)](https://aws.amazon.com/cloudwatch/)
[![Security](https://img.shields.io/github/actions/workflow/status/infrahouse/terraform-aws-rds/vuln-scanner-pr.yml?label=Security)](https://github.com/infrahouse/terraform-aws-rds/actions/workflows/vuln-scanner-pr.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

# terraform-aws-rds

An opinionated Terraform module for provisioning production-ready AWS RDS MySQL instances with
built-in observability, security hardening, and compliance tagging.

## Features

- **MySQL 8.x** with Performance Insights always enabled
- **CloudWatch alarms** with severity-based routing (urgent/high/normal)
- **PMM-style CloudWatch dashboard** — InnoDB rows, transactions, buffer pool, connections, locks, and more
- **Automatic SNS topic** creation with email subscriptions when explicit topic ARNs aren't provided
- **Storage encryption** (KMS) enabled by default
- **Multi-AZ** deployment by default
- **Vanta compliance tags** for SOC2/ISO27001 audits
- **Security group** with VPC-scoped access and optional CIDR/SG overrides
- **Secrets Manager** integration with configurable IAM reader access
- **Parameter group** family auto-derived from engine version

## Architecture

![Architecture](docs/assets/architecture.svg)

## Quick Start

```hcl
module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.1.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = module.vpc.private_subnet_ids

  alarm_emails = ["oncall@example.com", "dba@example.com"]
}
```

This creates a `db.t4g.medium` MySQL 8.4 instance with:
- Multi-AZ enabled
- 20 GiB gp3 storage (autoscales to 100 GiB)
- 7 CloudWatch alarms routed to an auto-created SNS topic
- A comprehensive CloudWatch dashboard
- Deletion protection enabled

## Documentation

Full documentation is available at
[infrahouse.github.io/terraform-aws-rds](https://infrahouse.github.io/terraform-aws-rds/).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5 |
| aws | ~> 6.0 |

## Usage

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

## Examples

See the [examples/](examples/) directory for complete working configurations.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.

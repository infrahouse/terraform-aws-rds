module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.1.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = var.subnet_ids

  alarm_emails = ["oncall@example.com"]
}

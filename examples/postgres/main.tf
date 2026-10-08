module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.3.0"

  engine = "postgres"
  # engine_version defaults to "18" (latest 18.x minor); pin a minor with e.g. "18.6"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = var.subnet_ids
  db_name      = "myapp"

  # Log statements slower than 500 ms (sets log_min_duration_statement = 500)
  long_query_time = 0.5

  parameters = [
    { name = "work_mem", value = "16384" } # KiB
  ]

  alarm_emails = ["oncall@example.com"]
}

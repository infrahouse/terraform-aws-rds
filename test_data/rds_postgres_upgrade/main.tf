# A PostgreSQL instance as aws-service-loopproof calls the module: alarm_emails and no notifications, so the module
# makes its own topic. test_upgrade_from_0_3_0 applies it with the release before first (module_override.tf).
module "rds" {
  source = "../../"

  engine = "postgres"

  environment  = "development"
  service_name = "test-rds-pgup"
  subnet_ids   = var.subnet_ids

  instance_class          = "db.t3.medium"
  multi_az                = false
  db_name                 = "testdb"
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
  backup_retention_period = 0

  alarm_emails = ["test@example.com"]

  vanta_owner = "test-rds-pgup"
}

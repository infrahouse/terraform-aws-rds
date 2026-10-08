resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_sns_topic" "test" {
  name = "test-rds-pg-alarms-${random_id.suffix.hex}"
}

module "rds" {
  source = "../../"

  engine = "postgres"

  environment  = "development"
  service_name = "test-rds-pg"
  subnet_ids   = var.subnet_ids

  # db.t4g has no Multi-AZ capacity in us-west-1c at times; db.t3.medium has the same 4 GiB and supports PI
  instance_class          = "db.t3.medium"
  db_name                 = "testdb"
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true
  backup_retention_period = 0

  alarm_emails = ["test@example.com"]

  notifications = {
    urgent = aws_sns_topic.test.arn
    high   = aws_sns_topic.test.arn
    normal = aws_sns_topic.test.arn
  }

  vanta_owner = "test-rds-pg"
}

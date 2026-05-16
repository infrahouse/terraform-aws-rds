resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_sns_topic" "test" {
  name = "test-rds-alarms-${random_id.suffix.hex}"
}

module "rds" {
  source = "../../"

  environment  = "development"
  service_name = "test-rds"
  subnet_ids   = var.subnet_ids

  instance_class          = "db.t4g.medium"
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

  vanta_owner = "test-rds"
}

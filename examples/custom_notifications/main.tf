resource "aws_sns_topic" "urgent" {
  name = "my-app-rds-urgent"
}

resource "aws_sns_topic" "normal" {
  name = "my-app-rds-normal"
}

module "rds" {
  source  = "registry.infrahouse.com/infrahouse/rds/aws"
  version = "0.1.0"

  environment  = "production"
  service_name = "my-app"
  subnet_ids   = var.subnet_ids

  instance_class        = "db.r6g.large"
  allocated_storage     = 100
  max_allocated_storage = 500

  alarm_emails = ["dba@example.com"]

  notifications = {
    urgent = aws_sns_topic.urgent.arn
    high   = aws_sns_topic.urgent.arn
    normal = aws_sns_topic.normal.arn
  }

  secret_readers = [
    "arn:aws:iam::123456789012:role/my-app-role"
  ]
}

locals {
  create_sns_topic = (
    var.notifications.urgent == null
    && var.notifications.high == null
    && var.notifications.normal == null
  )
}

resource "aws_sns_topic" "alarms" {
  count = local.create_sns_topic ? 1 : 0

  name_prefix       = "${var.service_name}-rds-alarms-"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-rds-alarms"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = local.create_sns_topic ? length(var.alarm_emails) : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alarm_emails[count.index]
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  create_sns_topic = var.notifications == null

  # The ARNs of the module's alarms, built from their names so that the key's policy doesn't depend on the alarms,
  # whose actions depend on the topic and its key.
  alarm_arns = [
    for name in values(local.alarm_names) : join(":", [
      "arn", data.aws_partition.current.partition, "cloudwatch", local.region,
      data.aws_caller_identity.current.account_id, "alarm", name,
    ])
  ]
}

resource "aws_sns_topic" "alarms" {
  count = local.create_sns_topic ? 1 : 0

  name_prefix = "${var.service_name}-rds-alarms-"
  # Not alias/aws/sns: CloudWatch can't publish to a topic under that key, whose policy nobody can change.
  kms_master_key_id = aws_kms_key.alarms[0].arn

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

# A customer-managed key, so that its policy can let CloudWatch use it. Not infrahouse/key/aws: it grants IAM
# principals only, with no conditions, and CloudWatch is a service principal, limited here to this module's alarms.
resource "aws_kms_key" "alarms" {
  count = local.create_sns_topic ? 1 : 0

  description         = "Encrypts the ${var.service_name} RDS alarms SNS topic; CloudWatch may use it for its alarms."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.alarms_key[0].json

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-rds-alarms"
  })
}

resource "aws_kms_alias" "alarms" {
  count = local.create_sns_topic ? 1 : 0

  name_prefix   = "alias/${var.service_name}-rds-alarms-"
  target_key_id = aws_kms_key.alarms[0].key_id
}

data "aws_iam_policy_document" "alarms_key" {
  count = local.create_sns_topic ? 1 : 0

  statement {
    # The default key policy: the account's IAM policies decide who else may use the key.
    sid       = "Account"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
  }

  statement {
    # What CloudWatch needs to publish an alarm's notification to an encrypted topic.
    sid       = "CloudWatchAlarms"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    # This module's alarms by name, not a prefix: "<service>-<environment>-*" can match the service's own alarms.
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = local.alarm_arns
    }
  }
}

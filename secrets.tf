data "aws_secretsmanager_secret" "master" {
  arn = aws_db_instance.this.master_user_secret[0].secret_arn
}

module "secret_policy" {
  count   = length(var.secret_readers) > 0 ? 1 : 0
  source  = "registry.infrahouse.com/infrahouse/secret-policy/aws"
  version = "0.2.1"

  readers = var.secret_readers
}

resource "aws_secretsmanager_secret_policy" "master" {
  count      = length(var.secret_readers) > 0 ? 1 : 0
  secret_arn = data.aws_secretsmanager_secret.master.arn
  policy     = module.secret_policy[0].policy_json
}

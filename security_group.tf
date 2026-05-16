resource "aws_security_group" "this" {
  name_prefix = "${var.service_name}-rds-"
  vpc_id      = data.aws_subnet.first.vpc_id
  description = "Security group for ${var.service_name} RDS instance"

  tags = merge(local.default_module_tags, {
    Name = "${var.service_name}-rds"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cidrs" {
  for_each = toset(local.allowed_cidrs)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "MySQL from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "security_groups" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "MySQL from ${each.value}"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "role_arn" {
  type        = string
  description = "IAM role ARN to assume"
  default     = null
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the RDS instance"
}

## Required variables

variable "environment" {
  type        = string
  description = "Environment name (lowercase, underscores only)"

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and underscores. Got: ${var.environment}"
  }
}

variable "service_name" {
  type        = string
  description = "Service name (used in naming and tags)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the DB subnet group (VPC derived from first subnet)"

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs required for Multi-AZ. Provided: ${length(var.subnet_ids)}"
  }
}

## Networking & Access

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Additional security group IDs allowed to connect to RDS"
  default     = []
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to connect to RDS (defaults to the VPC CIDR)"
  default     = null
}

## Instance Configuration

variable "instance_class" {
  type        = string
  description = "RDS instance class"
  default     = "db.t4g.medium"
}

variable "engine_version" {
  type        = string
  description = "MySQL engine version"
  default     = "8.4"
}

variable "allocated_storage" {
  type        = number
  description = "Initial storage in GiB"
  default     = 20
}

variable "max_allocated_storage" {
  type        = number
  description = "Max storage for autoscaling in GiB"
  default     = 100
}

variable "db_name" {
  type        = string
  description = "Database name to create on launch"
  default     = null
}

variable "username" {
  type        = string
  description = "Master username"
  default     = "admin"
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = true
}

variable "backup_retention_period" {
  type        = number
  description = "Days to retain automated backups"
  default     = 7
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
  default     = true
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot on deletion"
  default     = false
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately vs. maintenance window"
  default     = true
}

variable "storage_type" {
  type        = string
  description = "Storage type (gp3, io1, io2)"
  default     = "gp3"
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ARN for storage encryption (null = AWS managed key)"
  default     = null
}

variable "parameter_group_family" {
  type        = string
  description = "DB parameter group family (null = derived from engine_version)"
  default     = null
}

variable "long_query_time" {
  type        = number
  description = "Threshold in seconds for slow query logging"
  default     = 1
}

variable "parameters" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Additional DB parameters (merged with module defaults)"
  default     = []
}

variable "port" {
  type        = number
  description = "Database port"
  default     = 3306
}

variable "identifier_prefix" {
  type        = string
  description = "Identifier prefix for the RDS instance (auto-generated if null)"
  default     = null
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window"
  default     = "Mon:03:00-Mon:04:00"
}

variable "backup_window" {
  type        = string
  description = "Preferred backup window"
  default     = "02:00-02:30"
}

variable "read_only" {
  type        = bool
  description = "Set the database to read-only mode (immediate, no reboot)"
  default     = false
}

variable "performance_insights_retention_period" {
  type        = number
  description = "Performance Insights retention in days (7 = free tier, 31-731 = paid)"
  default     = 7
}

## Notifications (Severity-Based)

variable "alarm_emails" {
  type        = list(string)
  description = "Email addresses for alarm notifications (used when notifications is not set)"

  validation {
    condition     = length(var.alarm_emails) >= 1
    error_message = "At least one email address is required for alarm notifications."
  }
}

variable "notifications" {
  type = object({
    urgent = optional(string)
    high   = optional(string)
    normal = optional(string)
  })
  description = "SNS topic ARNs per severity tier (overrides alarm_emails when set)"
  default     = {}
}

## Alarm Thresholds

variable "alarm_cpu_threshold" {
  type        = number
  description = "CPU utilization % threshold"
  default     = 80
}

variable "alarm_cpu_evaluation_periods" {
  type        = number
  description = "CPU alarm evaluation periods"
  default     = 2
}

variable "alarm_cpu_period" {
  type        = number
  description = "CPU alarm period in seconds"
  default     = 300
}

variable "alarm_memory_percent" {
  type        = number
  description = "Freeable memory threshold as % of total instance memory"
  default     = 5
}

variable "alarm_memory_evaluation_periods" {
  type        = number
  description = "Memory alarm evaluation periods"
  default     = 2
}

variable "alarm_memory_period" {
  type        = number
  description = "Memory alarm period in seconds"
  default     = 900
}

variable "alarm_storage_percent_normal" {
  type        = number
  description = "Free storage % threshold for normal alarm"
  default     = 20
}

variable "alarm_storage_percent_high" {
  type        = number
  description = "Free storage % threshold for high alarm"
  default     = 10
}

variable "alarm_storage_percent_urgent" {
  type        = number
  description = "Free storage % threshold for urgent alarm"
  default     = 5
}

variable "alarm_storage_evaluation_periods" {
  type        = number
  description = "Storage alarm evaluation periods"
  default     = 1
}

variable "alarm_storage_period" {
  type        = number
  description = "Storage alarm period in seconds"
  default     = 300
}

variable "alarm_disk_queue_depth_threshold" {
  type        = number
  description = "Disk queue depth threshold"
  default     = 64
}

variable "alarm_disk_queue_evaluation_periods" {
  type        = number
  description = "Disk queue alarm evaluation periods"
  default     = 3
}

variable "alarm_disk_queue_period" {
  type        = number
  description = "Disk queue alarm period in seconds"
  default     = 300
}

variable "alarm_connections_threshold" {
  type        = number
  description = "Max database connections threshold (null = 80% of instance max)"
  default     = null
}

variable "alarm_connections_evaluation_periods" {
  type        = number
  description = "Connections alarm evaluation periods"
  default     = 2
}

variable "alarm_connections_period" {
  type        = number
  description = "Connections alarm period in seconds"
  default     = 300
}

## Vanta Compliance Tags

variable "vanta_owner" {
  type        = string
  description = "VantaOwner tag value (defaults to service_name)"
  default     = null
}

variable "vanta_non_prod" {
  type        = bool
  description = "VantaNonProd (null = derived from environment)"
  default     = null
}

variable "vanta_contains_user_data" {
  type        = bool
  description = "VantaContainsUserData"
  default     = true
}

variable "vanta_contains_ephi" {
  type        = bool
  description = "VantaContainsEPHI"
  default     = false
}

variable "vanta_description" {
  type        = string
  description = "VantaDescription"
  default     = "RDS MySQL database"
}

variable "vanta_user_data_stored" {
  type        = string
  description = "VantaUserDataStored (description of what user data)"
  default     = null
}

## Secret Access

variable "secret_readers" {
  type        = list(string)
  description = "IAM ARNs allowed to read the master password secret"
  default     = []
}

## General

variable "tags" {
  type        = map(string)
  description = "Additional tags to merge"
  default     = {}
}

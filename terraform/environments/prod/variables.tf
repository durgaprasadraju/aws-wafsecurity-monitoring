variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for VPC subnets (empty = auto-select first 2)"
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Email for security alerts and reports"
  type        = string
  default     = ""
}

variable "waf_rate_limit" {
  description = "WAF rate limit per IP (requests per 5 min)"
  type        = number
  default     = 2000
}

variable "enable_bot_control" {
  description = "Enable AWS Bot Control managed rule (additional cost)"
  type        = bool
  default     = false
}

variable "glue_crawler_schedule" {
  description = "EventBridge cron schedule for Glue crawler"
  type        = string
  default     = "cron(0 */4 * * ? *)"
}

variable "report_schedule_daily" {
  description = "EventBridge schedule for daily WAF report"
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "report_schedule_weekly" {
  description = "EventBridge schedule for weekly WAF report"
  type        = string
  default     = "cron(0 7 ? * MON *)"
}

variable "report_schedule_monthly" {
  description = "EventBridge schedule for monthly WAF report"
  type        = string
  default     = "cron(0 8 1 * ? *)"
}

variable "cloudwatch_dashboard_json_path" {
  description = "Optional path to custom CloudWatch dashboard JSON"
  type        = string
  default     = ""
}

variable "monitoring_instance_type" {
  description = "EC2 instance type for monitoring server"
  type        = string
  default     = "t3.medium"
}

variable "agent_instance_type" {
  description = "EC2 instance type for Node Exporter agent nodes"
  type        = string
  default     = "t3.micro"
}

variable "agent_count" {
  description = "Number of Node Exporter agent nodes"
  type        = number
  default     = 3
}

variable "key_name" {
  description = "EC2 key pair name for SSH access"
  type        = string
  default     = ""
}

variable "monitoring_server_ami" {
  description = "Override AMI for monitoring EC2 instances (empty = latest Amazon Linux 2023)"
  type        = string
  default     = ""
}

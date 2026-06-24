variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "lambda_role_arn" {
  type = string
}

variable "lambda_zip_path" {
  type = string
}

variable "athena_workgroup" {
  type = string
}

variable "athena_database" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "report_schedule_daily" {
  type    = string
  default = "cron(0 6 * * ? *)"
}

variable "report_schedule_weekly" {
  type    = string
  default = "cron(0 7 ? * MON *)"
}

variable "report_schedule_monthly" {
  type    = string
  default = "cron(0 8 1 * ? *)"
}

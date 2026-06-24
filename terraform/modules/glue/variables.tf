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

variable "s3_bucket_name" {
  type = string
}

variable "glue_crawler_role_arn" {
  type = string
}

variable "crawler_schedule" {
  type    = string
  default = "cron(0 */4 * * ? *)"
}

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

variable "web_acl_name" {
  type = string
}

variable "firehose_name" {
  type = string
}

variable "lambda_function_name" {
  type = string
}

variable "sns_topic_arn" {
  type = string
}

variable "dashboard_json_path" {
  type    = string
  default = ""
}

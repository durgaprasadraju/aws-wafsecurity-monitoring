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

variable "alb_arn" {
  type = string
}

variable "firehose_arn" {
  type = string
}

variable "waf_logging_role_arn" {
  type = string
}

variable "rate_limit" {
  type    = number
  default = 2000
}

variable "enable_bot_control" {
  type    = bool
  default = true
}

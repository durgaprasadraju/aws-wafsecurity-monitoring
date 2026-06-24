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

variable "alert_email" {
  type    = string
  default = ""
}

variable "kms_key_arn" {
  type = string
}

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

variable "database_name" {
  type = string
}

variable "s3_results_bucket" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

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

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "monitoring_server_ami" {
  type    = string
  default = ""
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "agent_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "agent_count" {
  type    = number
  default = 3
}

variable "key_name" {
  type    = string
  default = ""
}

variable "alb_dns_name" {
  type = string
}

variable "aws_region" {
  type = string
}

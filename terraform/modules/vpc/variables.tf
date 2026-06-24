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

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = []
}

variable "monitoring_public_access_cidrs" {
  description = "CIDRs allowed to reach Grafana/Prometheus on monitoring EC2 (use cautiously)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

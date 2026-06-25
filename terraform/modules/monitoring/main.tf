data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.monitoring_server_ami != "" ? var.monitoring_server_ami : data.aws_ami.amazon_linux.id
}

data "aws_caller_identity" "current" {}

resource "aws_instance" "monitoring_server" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_ids[0]
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name != "" ? var.key_name : null
  user_data = templatefile("${path.module}/../../../scripts/deployment/user_data_monitoring.sh", {
    project_name          = var.project_name
    alb_dns_name          = var.alb_dns_name
    environment           = var.environment
    aws_region            = var.aws_region
    account_id            = data.aws_caller_identity.current.account_id
    athena_database       = var.athena_database
    athena_workgroup      = var.athena_workgroup
    s3_bucket_name        = var.s3_bucket_name
    athena_dashboard_b64 = base64encode(replace(
      file("${path.module}/../../../dashboards/grafana/athena-log-analytics.json"),
      "__ATHENA_DATABASE__",
      var.athena_database
    ))
  })

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-monitoring-01"
    Role = "monitoring-server"
  })
}

resource "aws_instance" "agent_nodes" {
  count                  = var.agent_count
  ami                    = local.ami_id
  instance_type          = var.agent_instance_type
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.key_name != "" ? var.key_name : null
  user_data = file("${path.module}/../../../scripts/deployment/user_data_agent.sh")

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, {
    Name    = "${var.project_name}-${var.environment}-agent-${format("%02d", count.index + 2)}"
    Role    = "node-exporter"
    Project = var.project_name
  })
}

resource "aws_eip" "monitoring" {
  instance = aws_instance.monitoring_server.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-monitoring-eip"
  })
}

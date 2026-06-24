output "monitoring_server_id" {
  value = aws_instance.monitoring_server.id
}

output "monitoring_server_private_ip" {
  value = aws_instance.monitoring_server.private_ip
}

output "monitoring_server_public_ip" {
  value = aws_eip.monitoring.public_ip
}

output "agent_node_private_ips" {
  value = aws_instance.agent_nodes[*].private_ip
}

output "agent_node_ids" {
  value = aws_instance.agent_nodes[*].id
}

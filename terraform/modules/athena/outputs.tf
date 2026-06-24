output "workgroup_name" {
  value = aws_athena_workgroup.waf.name
}

output "named_query_ids" {
  value = { for k, v in aws_athena_named_query.queries : k => v.id }
}

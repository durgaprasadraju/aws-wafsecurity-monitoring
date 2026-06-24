output "database_name" {
  value = aws_glue_catalog_database.waf.name
}

output "table_name" {
  value = aws_glue_catalog_table.waf_logs.name
}

output "crawler_name" {
  value = aws_glue_crawler.waf_logs.name
}

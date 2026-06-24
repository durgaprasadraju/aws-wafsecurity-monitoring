output "bucket_id" {
  value = aws_s3_bucket.waf_logs.id
}

output "bucket_arn" {
  value = aws_s3_bucket.waf_logs.arn
}

output "bucket_name" {
  value = aws_s3_bucket.waf_logs.bucket
}

output "access_logs_bucket_id" {
  value = var.enable_access_logging ? aws_s3_bucket.access_logs[0].id : null
}

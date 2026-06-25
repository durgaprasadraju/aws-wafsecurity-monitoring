locals {
  project_name = "waf-security"
  environment  = "test"

  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = "security-team"
    CostCenter  = "security-ops"
  }
}

module "kms" {
  source       = "../../modules/kms"
  project_name = local.project_name
  environment  = local.environment
  tags         = local.common_tags
}

module "vpc" {
  source             = "../../modules/vpc"
  project_name       = local.project_name
  environment        = local.environment
  tags               = local.common_tags
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "s3" {
  source       = "../../modules/s3"
  project_name = local.project_name
  environment  = local.environment
  tags         = local.common_tags
  kms_key_arn  = module.kms.key_arn
}

module "sns" {
  source       = "../../modules/sns"
  project_name = local.project_name
  environment  = local.environment
  tags         = local.common_tags
  kms_key_arn  = module.kms.key_arn
  alert_email  = var.alert_email
}

module "iam" {
  source                    = "../../modules/iam"
  project_name              = local.project_name
  environment               = local.environment
  tags                      = local.common_tags
  s3_bucket_arn             = module.s3.bucket_arn
  kms_key_arn               = module.kms.key_arn
  athena_results_bucket_arn = module.s3.bucket_arn
  sns_topic_arn             = module.sns.reports_topic_arn
}

module "firehose" {
  source            = "../../modules/firehose"
  project_name      = local.project_name
  environment       = local.environment
  tags              = local.common_tags
  s3_bucket_arn     = module.s3.bucket_arn
  kms_key_arn       = module.kms.key_arn
  firehose_role_arn = module.iam.firehose_role_arn
}

module "alb" {
  source             = "../../modules/alb"
  project_name       = local.project_name
  environment        = local.environment
  tags               = local.common_tags
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.vpc.alb_security_group_id]
}

module "waf" {
  source               = "../../modules/waf"
  project_name         = local.project_name
  environment          = local.environment
  tags                 = local.common_tags
  alb_arn              = module.alb.alb_arn
  firehose_arn         = module.firehose.delivery_stream_arn
  waf_logging_role_arn = module.iam.waf_logging_role_arn
  rate_limit           = var.waf_rate_limit
  enable_bot_control   = var.enable_bot_control
}

module "glue" {
  source                = "../../modules/glue"
  project_name          = local.project_name
  environment           = local.environment
  tags                  = local.common_tags
  s3_bucket_name        = module.s3.bucket_name
  glue_crawler_role_arn = module.iam.glue_crawler_role_arn
  crawler_schedule      = var.glue_crawler_schedule
}

module "athena" {
  source            = "../../modules/athena"
  project_name      = local.project_name
  environment       = local.environment
  tags              = local.common_tags
  database_name     = module.glue.database_name
  s3_results_bucket = module.s3.bucket_name
  kms_key_arn       = module.kms.key_arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/report_generator"
  output_path = "${path.module}/.build/report_generator.zip"
  excludes    = ["requirements.txt", "__pycache__", "*.pyc", "tests"]
}

module "lambda" {
  source                  = "../../modules/lambda"
  project_name            = local.project_name
  environment             = local.environment
  tags                    = local.common_tags
  lambda_role_arn         = module.iam.lambda_report_role_arn
  lambda_zip_path         = data.archive_file.lambda_zip.output_path
  athena_workgroup        = module.athena.workgroup_name
  athena_database         = module.glue.database_name
  s3_bucket_name          = module.s3.bucket_name
  sns_topic_arn           = module.sns.reports_topic_arn
  kms_key_arn             = module.kms.key_arn
  report_schedule_daily   = var.report_schedule_daily
  report_schedule_weekly  = var.report_schedule_weekly
  report_schedule_monthly = var.report_schedule_monthly
}

module "cloudwatch" {
  source               = "../../modules/cloudwatch"
  project_name         = local.project_name
  environment          = local.environment
  tags                 = local.common_tags
  web_acl_name         = module.waf.web_acl_name
  firehose_name        = module.firehose.delivery_stream_name
  lambda_function_name = module.lambda.function_name
  sns_topic_arn        = module.sns.security_alerts_topic_arn
  dashboard_json_path  = var.cloudwatch_dashboard_json_path
}

module "monitoring" {
  source                = "../../modules/monitoring"
  project_name          = local.project_name
  environment           = local.environment
  tags                  = local.common_tags
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnet_ids
  security_group_id     = module.vpc.monitoring_security_group_id
  instance_profile_name = module.iam.ec2_monitoring_instance_profile_name
  instance_type         = var.monitoring_instance_type
  agent_instance_type   = var.agent_instance_type
  agent_count           = var.agent_count
  key_name              = var.key_name
  monitoring_server_ami = var.monitoring_server_ami
  alb_dns_name          = module.alb.alb_dns_name
  aws_region            = var.aws_region
  athena_database       = module.glue.database_name
  athena_workgroup      = module.athena.workgroup_name
  s3_bucket_name        = module.s3.bucket_name
}

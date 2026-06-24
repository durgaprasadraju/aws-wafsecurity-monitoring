resource "aws_glue_catalog_database" "waf" {
  name        = "${replace(var.project_name, "-", "_")}_${var.environment}_waf"
  description = "Glue catalog database for AWS WAF logs"

  tags = var.tags
}

resource "aws_glue_catalog_table" "waf_logs" {
  name          = "waf_logs"
  database_name = aws_glue_catalog_database.waf.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    "projection.enabled"  = "true"
    "projection.year.type"   = "integer"
    "projection.year.range"  = "2024,2030"
    "projection.month.type"  = "integer"
    "projection.month.range" = "1,12"
    "projection.month.digits" = "2"
    "projection.day.type"    = "integer"
    "projection.day.range"   = "1,31"
    "projection.day.digits"    = "2"
    "storage.location.template" = "s3://${var.s3_bucket_name}/waf-logs/year=$${year}/month=$${month}/day=$${day}/"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/waf-logs/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "waf-logs-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "timestamp"
      type = "bigint"
    }
    columns {
      name = "formatversion"
      type = "int"
    }
    columns {
      name = "webaclid"
      type = "string"
    }
    columns {
      name = "terminatingruleid"
      type = "string"
    }
    columns {
      name = "terminatingruletype"
      type = "string"
    }
    columns {
      name = "action"
      type = "string"
    }
    columns {
      name = "terminatingrulematchdetails"
      type = "array<struct<conditiontype:string,sensitivitylevel:string,location:string,matcheddata:array<string>>>"
    }
    columns {
      name = "httpsourcename"
      type = "string"
    }
    columns {
      name = "httpsourceid"
      type = "string"
    }
    columns {
      name = "rulegrouplist"
      type = "array<struct<rulegroupid:string,terminatingrule:struct<ruleid:string,action:string,rulematchdetails:array<struct<conditiontype:string,sensitivitylevel:string,location:string,matcheddata:array<string>>>>,nonterminatingmatchingrules:array<struct<ruleid:string,action:string,rulematchdetails:array<struct<conditiontype:string,sensitivitylevel:string,location:string,matcheddata:array<string>>>>>,excludedrules:string>>"
    }
    columns {
      name = "ratebasedrulelist"
      type = "array<struct<ratebasedruleid:string,limitkey:string,maxrateallowed:int>>"
    }
    columns {
      name = "nonterminatingmatchingrules"
      type = "array<struct<ruleid:string,action:string,rulematchdetails:array<struct<conditiontype:string,sensitivitylevel:string,location:string,matcheddata:array<string>>>>>"
    }
    columns {
      name = "requestheadersinserted"
      type = "array<struct<name:string,value:string>>"
    }
    columns {
      name = "responsecodesent"
      type = "int"
    }
    columns {
      name = "httprequest"
      type = "struct<clientip:string,country:string,headers:array<struct<name:string,value:string>>,uri:string,args:string,httpversion:string,httpmethod:string,requestid:string>"
    }
    columns {
      name = "labels"
      type = "array<struct<name:string>>"
    }
    columns {
      name = "captcharesponse"
      type = "struct<responsecode:string,solvetimestamp:string,failureReason:string>"
    }
    columns {
      name = "challengeResponse"
      type = "struct<responseCode:string,solveTimestamp:string,failureReason:string>"
    }
    columns {
      name = "ja3Fingerprint"
      type = "string"
    }
    columns {
      name = "ja4Fingerprint"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

resource "aws_glue_crawler" "waf_logs" {
  name          = "${var.project_name}-${var.environment}-waf-logs-crawler"
  role          = var.glue_crawler_role_arn
  database_name = aws_glue_catalog_database.waf.name

  s3_target {
    path = "s3://${var.s3_bucket_name}/waf-logs/"
  }

  schedule = var.crawler_schedule

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = var.tags
}

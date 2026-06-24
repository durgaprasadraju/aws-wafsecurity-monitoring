terraform {
  backend "s3" {
    bucket         = "waf-security-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "waf-security-terraform-locks"
  }
}

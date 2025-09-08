terraform {
  backend "s3" {
    bucket         = "prefect-assessment-yasir-bucket"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock" # <--- Use same name set in main.tf
    encrypt        = true
  }
}

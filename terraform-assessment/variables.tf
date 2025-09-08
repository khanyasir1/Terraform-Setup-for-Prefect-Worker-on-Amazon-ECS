variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name_tag" {
  type    = string
  default = "prefect-ecs"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "cluster_name" {
  type    = string
  default = "prefect-cluster"
}

variable "work_pool_name" {
  type    = string
  default = "ecs-work-pool"
}

variable "container_image" {
  type    = string
  default = "882142483262.dkr.ecr.us-east-1.amazonaws.com/my-prefect-flow:latest"
}

variable "desired_count" {
  type    = number
  default = 1
}

# If you want Terraform to CREATE the secret, set create_secret = true and populate prefect_api_key
variable "create_secret" {
  type    = bool
  default = false
}

variable "prefect_api_key" {
  type      = string
  default   = ""
  sensitive = true
}

# If you already have a secretsmanager secret ARN, pass it here (used when create_secret = false)
variable "prefect_secret_arn" {
  type    = string
  default = ""
}

variable "prefect_api_url" {
  type    = string
  default = "" # normally Prefect Cloud uses default endpoint; set if self-hosted server
}


variable "prefect_account_id" {
  type    = string
  default = "" # required if using Prefect Cloud
}


variable "prefect_workspace_id" {
  type    = string
  default = "" # required if using Prefect Cloud
}
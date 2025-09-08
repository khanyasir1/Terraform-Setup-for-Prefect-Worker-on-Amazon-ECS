## Infrastructure Breakdown

### 1. Provider & Variables

```hcl
terraform {
  required_version = ">= 1.2.0"
}
provider "aws" {
  region = var.region
}
```
**Explanation:**  
These blocks set the Terraform and AWS provider version requirements. This ensures your IaC is compatible with recent AWS features and resources, and specifies the deployment region.

***

### 2. Data Sources & Locals

```hcl
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

locals {
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)
  public_count  = length(local.azs)
  private_count = length(local.azs)
}
```
**Explanation:**  
- Fetches all AWS availability zones for the chosen region to guarantee high-availability by distributing resources across 3 AZs.  
- Sets up local variables helping automate subnet and resource distribution, making your Terraform code DRY and HA-friendly.

***

### 3. VPC

```hcl
resource "aws_vpc" "prefect" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = var.name_tag }
}
```
**Explanation:**  
Defines a dedicated and isolated virtual network (VPC) in AWS, with DNS resolution and hostnames, to securely contain all networking resources for the deployment.

***

### 4. Public Subnets

```hcl
resource "aws_subnet" "public" {
  count                   = local.public_count
  vpc_id                  = aws_vpc.prefect.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.name_tag}-public-${count.index + 1}"
  }
}
```
**Explanation:**  
Creates 3 public subnets in different AZs with unique CIDR blocks. These subnets allow resources launched in them (like a NAT Gateway) to receive public IPs and communicate with the internet.

***

### 5. Private Subnets

```hcl
resource "aws_subnet" "private" {
  count             = local.private_count
  vpc_id            = aws_vpc.prefect.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  tags = {
    Name = "${var.name_tag}-private-${count.index + 1}"
  }
}
```
**Explanation:**  
Creates 3 private subnets, each in a different AZ. These subnets isolate compute resources (ECS tasks/containers) from direct exposure to the internet, following AWS best practices for application security.

***

### 6. Internet Gateway (IGW)

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prefect.id
  tags = { Name = "${var.name_tag}-igw" }
}
```
**Explanation:**  
Attaches an IGW to the VPC, enabling resources in public subnets to directly connect to the internet.

***

### 7. Public Route Table and Association

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.prefect.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name_tag}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
```
**Explanation:**  
Defines routing so that public subnets send all outbound traffic (0.0.0.0/0) to the Internet Gateway. The association ensures all public subnets get internet connectivity.

***

### 8. NAT Gateway & Elastic IP

```hcl
resource "aws_eip" "nat" {
  tags = { Name = "${var.name_tag}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "${var.name_tag}-nat" }
}
```
**Explanation:**  
Creates a NAT gateway in a public subnet to allow private subnets secure, outbound internet access for pulling Docker images and OS updates, without exposing them directly.

***

### 9. Private Route Table and Association

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.prefect.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.name_tag}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
```
**Explanation:**  
Ensures all private subnets route their internet-bound traffic through the NAT gateway, guaranteeing secure updates and image pulls for containers without public IP exposure.

***

### 10. Security Group

```hcl
resource "aws_security_group" "prefect_sg" {
  name        = "${var.name_tag}-sg"
  description = "SG for Prefect ECS Fargate tasks"
  vpc_id      = aws_vpc.prefect.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.name_tag}-sg" }
}
```
**Explanation:**  
Defines a firewall (security group) to allow HTTP, HTTPS, and SSH to containers/services, and all outbound traffic. Critical for connectivity and endpoint availability.

***

### 11. CloudWatch Log Group

```hcl
resource "aws_cloudwatch_log_group" "prefect" {
  name              = "/ecs/${var.cluster_name}/dev-worker"
  retention_in_days = 14
  tags              = { Name = "${var.name_tag}-logs" }
}
```
**Explanation:**  
Creates a log group for capturing and storing Prefect worker logs in AWS CloudWatch for 14 days, aiding observability and debugging.

Here is comprehensive documentation in **English** for your `variables.tf`, `outputs.tf`, example `terraform.tfvars`, and `backend.tf` files. This style is professional, concise, and suitable for direct inclusion in a README or docs file.

***

## Variables (`variables.tf`)

Your configuration uses variables to make the setup reusable and parameterized. Below are the key variables:

```hcl
variable "region" {
  type    = string
  default = "us-east-1"
}
```
**Purpose:**  
Region in which all AWS resources are deployed. Change this to your preferred AWS region as needed.

***

```hcl
variable "name_tag" {
  type    = string
  default = "prefect-ecs"
}
```
**Purpose:**  
Defines a common name tag used for all AWS resources, assisting with identification and cost allocation.

***

```hcl
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
```
**Purpose:**  
Sets the IP address range for the VPC (Virtual Private Cloud), controlling internal networking.

***

```hcl
variable "cluster_name" {
  type    = string
  default = "prefect-cluster"
}
```
**Purpose:**  
Name of the ECS cluster where the Prefect worker is deployed.

***

```hcl
variable "work_pool_name" {
  type    = string
  default = "ecs-work-pool"
}
```
**Purpose:**  
The Prefect work pool from which the worker fetches and executes flows.

***

```hcl
variable "container_image" {
  type    = string
  default = "882142483262.dkr.ecr.us-east-1.amazonaws.com/my-prefect-flow:latest"
}
```
**Purpose:**  
Specifies the Docker image for the Prefect worker, typically residing in ECR (Elastic Container Registry).

***

```hcl
variable "desired_count" {
  type    = number
  default = 1
}
```
**Purpose:**  
Sets how many Prefect ECS worker tasks should run concurrently.

***

```hcl
variable "create_secret" {
  type    = bool
  default = false
}
```
**Purpose:**  
Controls whether Terraform should create a new Secrets Manager secret for the Prefect API key or use an existing secret ARN.

***

```hcl
variable "prefect_api_key" {
  type      = string
  default   = ""
  sensitive = true
}
```
**Purpose:**  
Holds your Prefect Cloud API key, securely stored when creating a new secret.

***

```hcl
variable "prefect_secret_arn" {
  type    = string
  default = ""
}
```
**Purpose:**  
ARN (Amazon Resource Name) of an existing Prefect API key secret, if not creating one with Terraform.

***

```hcl
variable "prefect_api_url" {
  type    = string
  default = ""
}
```
**Purpose:**  
URL for your Prefect API endpoint. Usually left empty for Prefect Cloud; used only for custom/self-hosted setups.

***

```hcl
variable "prefect_account_id" {
  type    = string
  default = ""
}
variable "prefect_workspace_id" {
  type    = string
  default = ""
}
```
**Purpose:**  
Account and workspace IDs from Prefect Cloud required for ECS-based connectivity and API routing.

***

## Outputs (`outputs.tf`)

After deployment, useful data is output for validation and future use.

```hcl
output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.prefect.arn
}
```
**Purpose:**  
Returns the unique ARN of the created ECS cluster.

***

```hcl
output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.prefect_service.name
}
```
**Purpose:**  
Outputs the ECS service name for reference and validation.

***

```hcl
output "prefect_secret_arn" {
  description = "Prefect API secret ARN (created or provided)"
  value       = local.secret_arn
}
```
**Purpose:**  
Displays the ARN of the Prefect API secret being used, whether created by Terraform or pre-existing.

***

```hcl
output "secret_arn_local" {
  value = local.secret_arn
}
```
**Purpose:**  
Exposes the locally computed secret ARN for use in scripting or modular workflows.

***

## Example `terraform.tfvars`

This file defines the values for your variables. (Sensitive/unique info is masked as "xxx".)

```hcl
create_secret         = true
prefect_api_key       = "xxx_PUT_YOUR_API_KEY_xxx"
prefect_secret_arn    = ""
prefect_account_id    = "xxx-account-id-xxxxxx"
prefect_workspace_id  = "xxx-workspace-id-xxxxxx"
```

**Purpose:**  
`terraform.tfvars` lets you conveniently set or override variable values without editing the main configuration. Never commit real API keys to public repos.

***

## Remote Backend (`backend.tf`)

```hcl
terraform {
  backend "s3" {
    bucket         = "prefect-assessment-yasir-bucket"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}
```
**Purpose:**  
Configures Terraform to store its state file remotely in an S3 bucket (with versioning and encryption).  
- **S3 Bucket:** Your deployment’s state file is safe and shared between team members.
- **Key:** Path to the state file in the bucket.
- **DynamoDB Table:** Enables state locking, preventing simultaneous conflicting changes during deployment.
- **Encrypt:** Ensures your IaC state is protected at rest.

This setup is critical for collaboration and reliability in any real DevOps environment.


## Architecture Diagram

This diagram shows the overall architecture of the Prefect worker deployment on AWS ECS including the VPC setup, ECS cluster, task flow, secrets integration, and networking components.

![Architecture Diagram](/images/architecture.png)

---

## VPC Setup

The VPC dashboard shows the 3 public and 3 private subnets distributed across multiple availability zones, alongside route tables, NAT gateway, and Internet gateway, providing a secure and resilient networking environment.

![VPC Setup](/images/vpc_setup.png)

---

## IAM Task Execution Role

IAM role named `prefect-task-execution-role` with necessary policies attached to allow ECS tasks to pull images, write logs, and access secrets from AWS Secrets Manager securely.

![IAM Role](/images/IAM-Role.png)

---

## Elastic Container Registry (ECR)

Amazon ECR repository stores the Docker image tagged as `my-prefect-flow:latest` used by the ECS tasks.

![ECR Repository](/images/ECR-Image.png)

---

## ECS Cluster and Service

ECS cluster `prefect-cluster` hosts the Fargate service named `dev-worker`. The service is deployed and tasks are in running status to process Prefect flow workloads.

![ECS Cluster](/images/ECS-Cluster.png)
![ECS Service ](/images/ECS-Service.png)
![ECS Service Tasks](/images/ECS-Task.png)

---

## ECS Worker Logs

Task logs captured in CloudWatch demonstrate the Prefect worker container startup, connection to the Prefect Cloud work pool, and task activity.

![ECS Task Logs](/images/ECS-CloudWatch-Logs.png)

---

## AWS Secrets Manager

Prefect API key is stored securely in AWS Secrets Manager under the secret named `prefect-ecs-prefect-api`. ECS tasks retrieve it using IAM permissions.

![Secrets Manager](/images/aws-secret-manager.png)






## Challenges and Learnings

- **Secrets Integration:**  
  Ensuring the secure injection of Prefect API keys via AWS Secrets Manager required careful policy configuration, including proper IAM permissions for ECS tasks. Troubleshooting permission errors helped reinforce best practices for secret management in cloud-native deployments.[4]

- **Networking & High Availability:**  
  Designing a resilient VPC with 3 public and 3 private subnets, NAT gateway, and correct routing required a good understanding of AWS networking. It was critical to ensure private ECS tasks could access the internet for pulling images, but remain shielded from inbound threats.

- **ECS Task Troubleshooting:**  
  Debugging ECS tasks when not starting or failing to register with Prefect Cloud was educational. Most issues were due to missing environment variables, networking misconfigurations, or IAM roles lacking granular permissions.

- **Terraform Modularity:**  
  Variable-driven infrastructure and remote state management (S3 + DynamoDB lock) provided a practical lesson in scalable, collaborative IaC and how to keep cloud state consistent for teams.

***

## Recommendations for Improvement

- **Enable Auto-Scaling:**  
  Implement ECS Service Auto Scaling policies to automatically adjust the number of Prefect worker tasks in response to queue depth or CPU/memory usage for better cost efficiency and high availability.[3][6]

- **Add Monitoring and Alerts:**  
  Integrate AWS CloudWatch Alarms and SNS notifications to alert on task failures, high resource utilization, or critical log messages for faster incident response.[1]

- **Centralized Logging & Tracing:**  
  Set up centralized, queryable log analysis (e.g., CloudWatch Insights) and consider distributed tracing tools for deeper workflow observability, especially for large or production workloads.[6]

- **Improve Cost Optimization:**  
  Use capacity providers like Fargate Spot for cost savings and regularly review resource utilization to right-size compute and memory allocations.

- **Add Backup, Versioning, and Rollback:**  
  Use S3 bucket versioning, periodic Terraform state backups, and consider a blue/green deployment mechanism for zero-downtime upgrades.

- **Add CI/CD Pipeline:**  
  Automate Terraform plan/apply and code validation using a CI/CD system to make deployments safer and more collaborative.


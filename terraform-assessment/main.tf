

# -------------------------------------------------------------------------------------
# Description : VPC + ECS Fargate + Service Discovery + IAM + Secure Secrets + Logging
# Author : Mohammed Yasir Khan
# Date : 08/09/2025
# -------------------------------------------------------------------------------------


# ---------------- PROVIDER & VARIABLES ----------------
terraform {
  required_version = ">= 1.2.0"
  # This block ensures Terraform is up-to-date.
}

provider "aws" {
  region = var.region
  # Sets AWS as our cloud to use and the region for our resources.

}

# ---------------- DATA SOURCES & LOCALS ----------------
data "aws_availability_zones" "available" {}
# Fetches all AZs in current region to optimize high-availability.

data "aws_caller_identity" "current" {}
# Fetch identity info on the current AWS account (helpful for outputs, tagging).


locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, 3)
  public_count  = length(local.azs)
  private_count = length(local.azs)
  # Compute first 3 AZs; used to evenly distribute resources for HA.

}


# ---------------- VPC ----------------
resource "aws_vpc" "prefect" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name_tag
  }
  # The VPC (Virtual Private Cloud) creates your own private network area in AWS.
  # Think of it as your “cloud datacenter” that you control.
  # All your subnets, security groups, ECS clusters and containers will live inside this VPC.
}

# ---------------- PUBLIC SUBNETS ----------------
resource "aws_subnet" "public" {
  count                   = local.public_count
  vpc_id                  = aws_vpc.prefect.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index) # splits by /8 sections (simple scheme)
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_tag}-public-${count.index + 1}"
  }
  # Public subnet: A slice of your VPC, assigned to one Availability Zone.
  # Allows EC2, NAT, and other resources to receive public IP addresses and access the Internet.
}

# ---------------- PRIVATE SUBNETS ----------------
resource "aws_subnet" "private" {
  count             = local.private_count
  vpc_id            = aws_vpc.prefect.id
  availability_zone = local.azs[count.index]
  # use different netnum to avoid overlap
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 10)

  tags = {
    Name = "${var.name_tag}-private-${count.index + 1}"
  }
  # Private subnet: A secure, non-internet-exposed part of your VPC within each AZ.
  # Used for ECS tasks and anything not needing public access.
}

# ---------------- INTERNET GATEWAY (IGW) ----------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.prefect.id
  tags = { Name = "${var.name_tag}-igw" }
  # Internet Gateway: Lets the VPC (and public subnets) connect to the public Internet.

}

# ---------------- PUBLIC ROUTE TABLE ----------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.prefect.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.name_tag}-public-rt" }
  # Public Route Table: Routes any ("0.0.0.0/0") outbound traffic to the Internet Gateway,
  # allowing anything in a public subnet to access the internet.
}

# Associate public route table to public subnets
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
    # Associates each public subnet with the route table so they use internet access rules.
}

# ---------------- NAT GATEWAY ----------------
resource "aws_eip" "nat" {
  # vpc = true
  tags = { Name = "${var.name_tag}-nat-eip" }
  # Elastic IP: A persistent public IP, required for the NAT Gateway.

}



# NAT Gateway in first public subnet (single NAT)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "${var.name_tag}-nat" }
   # NAT Gateway: Allows private subnets to reach the Internet for patches, updates, images, etc.,
  # without exposing resources to incoming traffic from the outside.
}

# ---------------- PRIVATE ROUTE TABLE ----------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.prefect.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.name_tag}-private-rt" }
   # Private Route Table: All outbound traffic from private subnets is routed through NAT Gateway.
  # Ensures secure, indirect internet access only.
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
    # Associates each private subnet with its specific route table and NAT.

}

# ---------------- SECURITY GROUP ----------------
resource "aws_security_group" "prefect_sg" {
  name        = "${var.name_tag}-sg"
  description = "SG for Prefect ECS Fargate tasks"
  vpc_id      = aws_vpc.prefect.id


# --- Inbound Rules ---
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # Allow requests on port 80 (HTTP)—for website access.
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # Allow SSH (port 22)—so you can log in remotely for maintenance.
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    # Allow HTTPS (port 443)—for secure website access.
  }


  # allow outbound to internet
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # keep ingress empty (no inbound from internet). Adjust if you need ports.
  tags = { Name = "${var.name_tag}-sg" }
}

# ---------------- CLOUDWATCH LOG GROUP ----------------
resource "aws_cloudwatch_log_group" "prefect" {
  name              = "/ecs/${var.cluster_name}/dev-worker"
  retention_in_days = 14
  tags              = { Name = "${var.name_tag}-logs" }
  # Stores logs from ECS containers for 14 days for troubleshooting & observability.
}

# ---------------- IAM ROLES AND POLICIES ----------------
resource "aws_iam_role" "task_execution_role" {
  name = "prefect-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
   tags = { Name = var.name_tag }
  # IAM Role: Delegates AWS permissions for ECS Fargate containers to access AWS resources.
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  # Attach AWS-provided policy empowering ECS to pull images, write logs, etc.
}

# Attach ECR read-only access so ECS tasks can pull images
resource "aws_iam_role_policy_attachment" "ecs_task_execution_ecr" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


resource "aws_iam_role_policy" "secrets_policy" {
  name = "prefect-secrets-policy"
  role = aws_iam_role.task_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = [
        "secretsmanager:CreateSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      Resource = local.secret_arn != null ? local.secret_arn : "*"
    }]
  })
  # Custom inline policy: Grants tasks ability to securely fetch Prefect API key from Secrets Manager.
}

# ---------------- SECRETS MANAGER ----------------
resource "aws_secretsmanager_secret" "prefect_api" {
  count = var.create_secret ? 1 : 0
  name  = "${var.name_tag}-prefect-api"
  tags  = { Name = var.name_tag }
  # Defines a new Secrets Manager secret to securely store the Prefect Cloud API Key.
}

resource "aws_secretsmanager_secret_version" "prefect_api_value" {
  count        = var.create_secret ? 1 : 0
  secret_id    = aws_secretsmanager_secret.prefect_api[0].id
  secret_string = var.prefect_api_key
  # The actual secret value (API key) versioned and stored.
}



locals {
  secret_arn = var.create_secret ? try(aws_secretsmanager_secret.prefect_api[0].arn, null) : (
    length(var.prefect_secret_arn) > 0 ? var.prefect_secret_arn : null
  )
# Picks the secret ARN (either created or provided) for usage in IAM and ECS task definitions.

}

# ---------------- ECR REPOSITORY ----------------
resource "aws_ecr_repository" "my_prefect_flow" {
  name = "my-prefect-flow"
  force_delete = true
  # Elastic Container Registry (ECR): Stores Docker images for your Prefect workers.
}

# ---------------- ECS CLUSTER ----------------
resource "aws_ecs_cluster" "prefect" {
  name = var.cluster_name
  tags = { Name = var.name_tag }
  # ECS cluster: Where all ECS tasks/services will be launched.
}

# ---------------- SERVICE DISCOVERY (PRIVATE DNS) ----------------
resource "aws_service_discovery_private_dns_namespace" "prefect_ns" {
  name        = "default.prefect.local"
  vpc         = aws_vpc.prefect.id
  description = "Prefect private DNS namespace"
  # Creates a private DNS zone for ECS internal service discovery.
}


resource "aws_service_discovery_service" "dev_worker_sd" {
  name = "dev-worker-sd"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.prefect_ns.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
  #   # DNS Service Discovery: ECS tasks/services can find each other by private DNS.

}

# ---------------- ECS TASK DEFINITION ----------------
resource "aws_ecs_task_definition" "prefect_worker" {
  family                   = "dev-worker"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  task_role_arn            = aws_iam_role.task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "dev-worker"
      image     = var.container_image
      essential = true

      environment = [
        {
          name  = "PREFECT_API_URL"
          value = "https://api.prefect.cloud/api/accounts/${var.prefect_account_id}/workspaces/${var.prefect_workspace_id}"
        }
      ]
      secrets = local.secret_arn != null ? [{
        name      = "PREFECT_API_KEY"
        valueFrom = local.secret_arn
      }] : []

      command = ["prefect", "worker", "start", "--pool", var.work_pool_name]
      # Launches and registers Prefect worker with the correct pool.

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.prefect.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "prefect"
        }
      }
    }
  ])
  depends_on = [
    aws_secretsmanager_secret.prefect_api,
    aws_secretsmanager_secret_version.prefect_api_value
  ]
  tags = { Name = "${var.name_tag}-taskdef" }
  # Task definition: Blueprint for running containerized Prefect workers on ECS Fargate.
}

# ---------------- ECS SERVICE ----------------
resource "aws_ecs_service" "prefect_service" {
  name            = "dev-worker"
  cluster         = aws_ecs_cluster.prefect.id
  task_definition = aws_ecs_task_definition.prefect_worker.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.prefect_sg.id]
    assign_public_ip = false
    # Runs ECS tasks in private subnets (inside a secure network).
  }

  service_registries {
    registry_arn = aws_service_discovery_service.dev_worker_sd.arn
    # Registers task with cloud DNS for internal communication.
  }

  depends_on = [aws_nat_gateway.nat]
  tags       = { Name = "${var.name_tag}-service" }
  # ECS Service: Manages the desired number of Prefect worker tasks, provides high availability.
}



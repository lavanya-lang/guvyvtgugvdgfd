# Creates a production-grade VPC in us-east-1 with 2 AZs, 2 public + 2 private subnets, IGW, 2 NAT gateways, public/private route tables and associations, public/private NACLs, 2 gateway VPC endpoints (S3 and DynamoDB), a security group allowing SSH/HTTP, and a t3.micro EC2 instance in the first public subnet with a public IP. VPC DNS hostnames/support are disabled as requested and no `vpc = true` is used.
# Generated Terraform code for AWS in us-east-1

terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.25.0"
    }
  }
}

variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "vpc"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.project))
    error_message = "project must contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name used for resource naming"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]+$", var.environment))
    error_message = "environment must contain only letters, numbers, and hyphens."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_dns_hostnames" {
  description = "Whether to enable DNS hostnames in the VPC"
  type        = bool
  default     = false
}

variable "enable_dns_support" {
  description = "Whether to enable DNS support in the VPC"
  type        = bool
  default     = false
}

variable "instance_tenancy" {
  description = "VPC tenancy setting"
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default"], var.instance_tenancy)
    error_message = "instance_tenancy must be default."
  }
}

variable "availability_zones_count" {
  description = "Number of availability zones to use (fixed at 2 for this design)"
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zones_count == 2
    error_message = "This configuration requires exactly 2 availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (must be 2 CIDRs for 2 AZs)"
  type        = list(string)
  default     = ["10.0.0.0/20", "10.0.16.0/20"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly 2 CIDRs."
  }
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (must be 2 CIDRs for 2 AZs)"
  type        = list(string)
  default     = ["10.0.128.0/20", "10.0.144.0/20"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly 2 CIDRs."
  }
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ec2_key_name" {
  description = "Existing EC2 key pair name to enable SSH access"
  type        = string

  validation {
    condition     = length(var.ec2_key_name) > 0
    error_message = "ec2_key_name must be a non-empty existing key pair name in the target region."
  }
}

variable "tags" {
  description = "Additional tags to apply to all taggable resources"
  type        = map(string)
  default     = {}
}

provider "aws" {
  {{block_to_replace_cred}}

  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zones_count)

  name_prefix = "${var.project}-${var.environment}"

  tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project
    },
    var.tags
  )
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  instance_tenancy     = var.instance_tenancy

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  tags   = merge(local.tags, { Name = "${local.name_prefix}-igw" })
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  availability_zone = local.azs[count.index]
  cidr_block        = var.public_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-subnet-public-${count.index + 1}" })
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  availability_zone = local.azs[count.index]
  cidr_block        = var.private_subnet_cidrs[count.index]
  vpc_id            = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-subnet-private-${count.index + 1}" })
}

resource "aws_eip" "nat" {
  count = length(local.azs)

  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eip-nat-${count.index + 1}" })
}

resource "aws_nat_gateway" "main" {
  count = length(local.azs)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nat-${count.index + 1}" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  tags   = merge(local.tags, { Name = "${local.name_prefix}-rt-public" })
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_default" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
  route_table_id         = aws_route_table.public.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_route_table" "private" {
  count = length(local.azs)

  tags   = merge(local.tags, { Name = "${local.name_prefix}-rt-private-${count.index + 1}" })
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "private_default" {
  count = length(local.azs)

  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
  route_table_id         = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  route_table_id = aws_route_table.private[count.index].id
  subnet_id      = aws_subnet.private[count.index].id
}

resource "aws_network_acl" "public" {
  subnet_ids = [for s in aws_subnet.public : s.id]
  vpc_id     = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nacl-public" })
}

resource "aws_network_acl_rule" "public_ingress_ssh" {
  cidr_block     = "0.0.0.0/0"
  egress         = false
  from_port      = 22
  network_acl_id = aws_network_acl.public.id
  protocol       = "tcp"
  rule_action    = "allow"
  rule_number    = 100
  to_port        = 22
}

resource "aws_network_acl_rule" "public_ingress_http" {
  cidr_block     = "0.0.0.0/0"
  egress         = false
  from_port      = 80
  network_acl_id = aws_network_acl.public.id
  protocol       = "tcp"
  rule_action    = "allow"
  rule_number    = 110
  to_port        = 80
}

resource "aws_network_acl_rule" "public_ingress_ephemeral" {
  cidr_block     = "0.0.0.0/0"
  egress         = false
  from_port      = 1024
  network_acl_id = aws_network_acl.public.id
  protocol       = "tcp"
  rule_action    = "allow"
  rule_number    = 120
  to_port        = 65535
}

resource "aws_network_acl_rule" "public_egress_all" {
  cidr_block     = "0.0.0.0/0"
  egress         = true
  from_port      = 0
  network_acl_id = aws_network_acl.public.id
  protocol       = "-1"
  rule_action    = "allow"
  rule_number    = 100
  to_port        = 0
}

resource "aws_network_acl" "private" {
  subnet_ids = [for s in aws_subnet.private : s.id]
  vpc_id     = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nacl-private" })
}

resource "aws_network_acl_rule" "private_ingress_all_from_vpc" {
  cidr_block     = aws_vpc.main.cidr_block
  egress         = false
  from_port      = 0
  network_acl_id = aws_network_acl.private.id
  protocol       = "-1"
  rule_action    = "allow"
  rule_number    = 100
  to_port        = 0
}

resource "aws_network_acl_rule" "private_egress_all" {
  cidr_block     = "0.0.0.0/0"
  egress         = true
  from_port      = 0
  network_acl_id = aws_network_acl.private.id
  protocol       = "-1"
  rule_action    = "allow"
  rule_number    = 100
  to_port        = 0
}

resource "aws_security_group" "web" {
  description = "Allow SSH and HTTP"
  name        = "${local.name_prefix}-sg-web"
  vpc_id      = aws_vpc.main.id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "All egress"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg-web" })
}

resource "aws_vpc_endpoint" "s3" {
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_id       = aws_vpc.main.id

  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id]
  )

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpce-s3" })

  vpc_endpoint_type = "Gateway"
}

resource "aws_vpc_endpoint" "dynamodb" {
  service_name = "com.amazonaws.${var.region}.dynamodb"
  vpc_id       = aws_vpc.main.id

  route_table_ids = concat(
    [aws_route_table.public.id],
    [for rt in aws_route_table.private : rt.id]
  )

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpce-dynamodb" })

  vpc_endpoint_type = "Gateway"
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  associate_public_ip_address = true
  instance_type               = var.ec2_instance_type
  key_name                    = var.ec2_key_name
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.web.id]

  root_block_device {
    encrypted   = true
    volume_size = 8
    volume_type = "gp3"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-ec2-web" })
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = [for s in aws_subnet.private : s.id]
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways"
  value       = [for ngw in aws_nat_gateway.main : ngw.id]
}

output "vpc_endpoint_ids" {
  description = "IDs of the VPC endpoints"
  value       = [aws_vpc_endpoint.s3.id, aws_vpc_endpoint.dynamodb.id]
}

output "security_group_id" {
  description = "ID of the security group allowing SSH and HTTP"
  value       = aws_security_group.web.id
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.web.id
}

output "ec2_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}
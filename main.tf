# Fixes the unsupported output attribute by removing the invalid aws_autoscaling_group.main.instances reference. The ASG name output remains.
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

variable "environment" {
  description = "Environment name used for tagging."
  type        = string
  default     = "prod"

  validation {
    condition     = length(var.environment) > 0
    error_message = "environment must be a non-empty string."
  }
}

variable "managed_by" {
  description = "Tag value indicating the provisioning system."
  type        = string
  default     = "terraform"

  validation {
    condition     = length(var.managed_by) > 0
    error_message = "managed_by must be a non-empty string."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group."
  type        = string
  default     = "t3.medium"

  validation {
    condition     = length(var.instance_type) > 0
    error_message = "instance_type must be a non-empty string."
  }
}

variable "desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_capacity >= 0
    error_message = "desired_capacity must be >= 0."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 2

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be >= 0."
  }
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 4

  validation {
    condition     = var.max_size >= 0
    error_message = "max_size must be >= 0."
  }
}

variable "vpc_id" {
  description = "Existing VPC ID where the Auto Scaling Group security group will be created."
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "vpc_id must look like an AWS VPC ID (start with 'vpc-')."
  }
}

variable "subnet_ids" {
  description = "Existing subnet IDs to place the Auto Scaling Group instances into."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids must contain at least one subnet ID."
  }
}

variable "asg_name" {
  description = "Name for the Auto Scaling Group."
  type        = string
  default     = "prod-asg"

  validation {
    condition     = length(var.asg_name) > 0
    error_message = "asg_name must be a non-empty string."
  }
}

variable "launch_template_name" {
  description = "Name for the EC2 launch template."
  type        = string
  default     = "prod-lt"

  validation {
    condition     = length(var.launch_template_name) > 0
    error_message = "launch_template_name must be a non-empty string."
  }
}

variable "ssh_ingress_cidr_blocks" {
  description = "Optional CIDR blocks allowed to SSH to instances. Leave empty to disable SSH ingress."
  type        = list(string)
  default     = []
}

provider "aws" {
  {{block_to_replace_cred}}

  region = "us-east-1"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "asg" {
  description = "Security group for ASG instances"
  name_prefix = "${var.asg_name}-"
  vpc_id      = var.vpc_id

  tags = {
    Environment = var.environment
    Name        = "${var.asg_name}-sg"
    managed_by  = var.managed_by
  }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 0
  ip_protocol       = "-1"
  security_group_id = aws_security_group.asg.id
  to_port           = 0

  tags = {
    Environment = var.environment
    Name        = "${var.asg_name}-sg-egress-all"
    managed_by  = var.managed_by
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = { for cidr in var.ssh_ingress_cidr_blocks : cidr => cidr }

  cidr_ipv4         = each.value
  from_port         = 22
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.asg.id
  to_port           = 22

  tags = {
    Environment = var.environment
    Name        = "${var.asg_name}-sg-ingress-ssh-${replace(each.key, "/", "-")}" 
    managed_by  = var.managed_by
  }
}

resource "aws_launch_template" "main" {
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  name          = var.launch_template_name

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
  }

  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.asg.id]
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Environment = var.environment
      Name        = var.asg_name
      managed_by  = var.managed_by
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Environment = var.environment
      Name        = var.asg_name
      managed_by  = var.managed_by
    }
  }

  update_default_version = true

  tags = {
    Environment = var.environment
    Name        = var.launch_template_name
    managed_by  = var.managed_by
  }
}

resource "aws_autoscaling_group" "main" {
  desired_capacity    = var.desired_capacity
  health_check_type   = "EC2"
  max_size            = var.max_size
  min_size            = var.min_size
  name                = var.asg_name
  vpc_zone_identifier = var.subnet_ids

  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  tag {
    key                 = "Environment"
    propagate_at_launch = true
    value               = var.environment
  }

  tag {
    key                 = "managed_by"
    propagate_at_launch = true
    value               = var.managed_by
  }

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = var.asg_name
  }
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.main.name
}
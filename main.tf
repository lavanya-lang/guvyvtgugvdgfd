# Fixes the unsupported output attribute by removing the invalid reference to aws_autoscaling_group.main.instances (not exported by the resource). All other resources remain unchanged.
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

variable "asg_desired_capacity" {
  description = "Desired number of instances in the Auto Scaling Group."
  type        = number
  default     = 2

  validation {
    condition     = var.asg_desired_capacity >= 0
    error_message = "asg_desired_capacity must be >= 0."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 4

  validation {
    condition     = var.asg_max_size >= 1
    error_message = "asg_max_size must be >= 1."
  }
}

variable "asg_min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 2

  validation {
    condition     = var.asg_min_size >= 0
    error_message = "asg_min_size must be >= 0."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group instances."
  type        = string
  default     = "t3.medium"
}

variable "project" {
  description = "Project identifier used for naming/tagging."
  type        = string
  default     = "app"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.project))
    error_message = "project must contain only letters, numbers, underscores, and hyphens."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the Auto Scaling Group. Must be in the same VPC as vpc_id."
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID where the Auto Scaling Group and security group will be created."
  type        = string
}

provider "aws" {
  {{block_to_replace_cred}}
  region = "us-east-1"
}

locals {
  name_prefix = "${var.project}-prod"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "ec2" {
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  name               = "${local.name_prefix}-ec2-role"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "asg" {
  description = "Security group for ${local.name_prefix} ASG"
  name        = "${local.name_prefix}-asg-sg"
  vpc_id      = var.vpc_id

  # No ingress by default (least privilege). Add explicit rules as needed.

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Project     = var.project
  }
}

resource "aws_launch_template" "main" {
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  name_prefix   = "${local.name_prefix}-lt-"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
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
      Environment = "prod"
      ManagedBy   = "terraform"
      Name        = "${local.name_prefix}-asg"
      Project     = var.project
    }
  }

  tag_specifications {
    resource_type = "volume"

    tags = {
      Environment = "prod"
      ManagedBy   = "terraform"
      Project     = var.project
    }
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Project     = var.project
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
set -euo pipefail

dnf -y update
EOF
  )
}

resource "aws_autoscaling_group" "main" {
  desired_capacity    = var.asg_desired_capacity
  max_size            = var.asg_max_size
  min_size            = var.asg_min_size
  name                = "${local.name_prefix}-asg"
  vpc_zone_identifier = var.subnet_ids

  health_check_grace_period = 300
  health_check_type         = "EC2"

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Production-leaning safety behavior
  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 90
    }

    triggers = ["launch_template"]
  }

  tag {
    key                 = "Environment"
    propagate_at_launch = true
    value               = "prod"
  }

  tag {
    key                 = "ManagedBy"
    propagate_at_launch = true
    value               = "terraform"
  }

  tag {
    key                 = "Project"
    propagate_at_launch = true
    value               = var.project
  }
}

resource "aws_autoscaling_policy" "cpu_target" {
  autoscaling_group_name = aws_autoscaling_group.main.name
  name                   = "${local.name_prefix}-cpu-target"
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50
  }
}

output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.main.name
}
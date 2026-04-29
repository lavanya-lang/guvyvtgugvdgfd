# Fixes the validation error by removing the invalid output attribute aws_autoscaling_group.main.instances (not exported by this resource in AWS provider v6.25.0).
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
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the Auto Scaling Group instances."
  type        = string
  default     = "t3.micro"
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

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 4

  validation {
    condition     = var.max_size >= 0
    error_message = "max_size must be >= 0."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 1

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be >= 0."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the Auto Scaling Group. Provide at least 2 subnets across different AZs for production."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must contain at least 1 subnet ID."
  }
}

variable "vpc_id" {
  description = "VPC ID where the security group (and instances) will be deployed."
  type        = string
}

variable "asg_name" {
  description = "Name for the Auto Scaling Group."
  type        = string
  default     = "ec2-asg"

  validation {
    condition     = length(var.asg_name) >= 1
    error_message = "asg_name must not be empty."
  }
}

variable "tags" {
  description = "Tags to apply to resources."
  type        = map(string)
  default = {
    ManagedBy = "terraform"
  }
}

variable "ssh_ingress_cidrs" {
  description = "Optional CIDR blocks allowed to SSH to instances. For production, prefer SSM and keep this empty."
  type        = list(string)
  default     = []
}

provider "aws" {
  region = var.region

  {{block_to_replace_cred}}
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
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

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  dynamic "ingress" {
    for_each = toset(var.ssh_ingress_cidrs)
    content {
      cidr_blocks = [ingress.value]
      description = "Optional SSH access"
      from_port   = 22
      protocol    = "tcp"
      to_port     = 22
    }
  }

  tags = merge(var.tags, {
    Name = "${var.asg_name}-sg"
  })
}

resource "aws_launch_template" "main" {
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type
  name_prefix   = "${var.asg_name}-lt-"

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
    tags = merge(var.tags, {
      Name = "${var.asg_name}-instance"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.asg_name}-volume"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.asg_name}-launch-template"
  })
}

resource "aws_autoscaling_group" "main" {
  desired_capacity    = var.desired_capacity
  max_size            = var.max_size
  min_size            = var.min_size
  name                = var.asg_name
  vpc_zone_identifier = var.subnet_ids

  health_check_grace_period = 300
  health_check_type         = "EC2"

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 90
    }

    triggers = ["tag"]
  }

  termination_policies = ["OldestLaunchTemplate", "OldestInstance"]

  tag {
    key                 = "ManagedBy"
    propagate_at_launch = true
    value               = "terraform"
  }

  dynamic "tag" {
    for_each = { for k, v in var.tags : k => v if k != "ManagedBy" }
    content {
      key                 = tag.key
      propagate_at_launch = true
      value               = tag.value
    }
  }

  tag {
    key                 = "Name"
    propagate_at_launch = true
    value               = "${var.asg_name}-instance"
  }

  lifecycle {
    create_before_destroy = true
  }
}

output "asg_name" {
  description = "Auto Scaling Group name."
  value       = aws_autoscaling_group.main.name
}

output "launch_template_id" {
  description = "Launch template ID used by the Auto Scaling Group."
  value       = aws_launch_template.main.id
}

output "security_group_id" {
  description = "Security group ID attached to ASG instances."
  value       = aws_security_group.asg.id
}
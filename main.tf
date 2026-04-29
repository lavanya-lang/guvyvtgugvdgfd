# Creates an S3 bucket named 'uitqw' (with encryption and public access blocked) and an IAM user with read-only permissions (ListBucket + GetObject) restricted to that bucket only, in us-east-1.
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

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket to create and restrict IAM access to."
  type        = string
  default     = "uitqw"

  validation {
    condition     = length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63
    error_message = "bucket_name must be between 3 and 63 characters."
  }
}

variable "iam_user_name" {
  description = "Name of the IAM user that will be granted read-only access to the bucket."
  type        = string
  default     = "uitqw-s3-readonly"

  validation {
    condition     = length(var.iam_user_name) >= 1 && length(var.iam_user_name) <= 64
    error_message = "iam_user_name must be between 1 and 64 characters."
  }
}

variable "tags" {
  description = "Tags to apply to supported resources."
  type        = map(string)
  default = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Project     = "uitqw"
  }
}

provider "aws" {
  region = var.aws_region
  {{block_to_replace_cred}}
}

resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "main" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.main.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_user" "main" {
  name = var.iam_user_name

  tags = var.tags
}

resource "aws_iam_user_policy" "s3_readonly_bucket_only" {
  name = "${var.iam_user_name}-s3-readonly-${var.bucket_name}"
  user = aws_iam_user.main.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.main.arn
      },
      {
        Sid    = "AllowGetObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.main.arn}/*"
      }
    ]
  })
}

output "s3_bucket_name" {
  description = "Name of the created S3 bucket."
  value       = aws_s3_bucket.main.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket."
  value       = aws_s3_bucket.main.arn
}

output "iam_user_name" {
  description = "Name of the created IAM user."
  value       = aws_iam_user.main.name
}
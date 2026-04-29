# Creates an encrypted S3 bucket named 'jeiruy47' (with versioning and public-access blocking) and an IAM user with a custom IAM policy attached granting read-only access to that specific bucket and its objects in us-east-1.
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
  description = "Name of the S3 bucket to create."
  type        = string
  default     = "jeiruy47"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (lowercase letters, numbers, dots, hyphens; 3-63 chars)."
  }
}

variable "iam_user_name" {
  description = "Name of the IAM user to create."
  type        = string
  default     = "jeiruy47-s3-readonly"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.iam_user_name))
    error_message = "iam_user_name must be a valid IAM user name (1-64 chars, allowed: alphanumerics and +=,.@_-)."
  }
}

variable "tags" {
  description = "Tags to apply to supported resources."
  type        = map(string)
  default = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

provider "aws" {
  region = var.aws_region
  {{block_to_replace_cred}}
}

resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  block_public_acls       = true
  block_public_policy     = true
  bucket                  = aws_s3_bucket.main.id
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "main" {
  bucket = aws_s3_bucket.main.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_iam_user" "readonly" {
  name = var.iam_user_name
  tags = var.tags
}

data "aws_iam_policy_document" "s3_readonly_bucket" {
  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:GetBucketPolicyStatus",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions"
    ]

    resources = [
      aws_s3_bucket.main.arn
    ]

    sid = "S3ReadOnlyBucket"
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionAttributes",
      "s3:GetObjectVersionTagging",
      "s3:ListMultipartUploadParts"
    ]

    resources = [
      "${aws_s3_bucket.main.arn}/*"
    ]

    sid = "S3ReadOnlyObjects"
  }
}

resource "aws_iam_policy" "s3_readonly_bucket" {
  name   = "${var.iam_user_name}-policy"
  policy = data.aws_iam_policy_document.s3_readonly_bucket.json
  tags   = var.tags
}

resource "aws_iam_user_policy_attachment" "readonly" {
  policy_arn = aws_iam_policy.s3_readonly_bucket.arn
  user       = aws_iam_user.readonly.name
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
  description = "Name of the IAM user with read-only access to the bucket."
  value       = aws_iam_user.readonly.name
}

output "iam_policy_arn" {
  description = "ARN of the IAM policy granting read-only access to the bucket."
  value       = aws_iam_policy.s3_readonly_bucket.arn
}
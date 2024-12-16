provider "aws" {
  region = "us-west-2"  # Change to your desired region
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.backend_bucket
  acl    = "private"

  versioning {
    enabled = true
  }

  tags = {
    Name        = "Terraform State Bucket"
    Environment = var.environment
  }
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.dynamodb_table
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform Lock Table"
    Environment = var.environment
  }
}

resource "aws_iam_role" "github_oidc_role" {
  name = "GitHubActionsOIDCRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "GitHub OIDC Role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy" "custom_s3_policy" {
  name   = "CustomS3Policy"
  role   = aws_iam_role.github_oidc_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${aws_s3_bucket.terraform_state.arn}/*",
          aws_s3_bucket.terraform_state.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "custom_dynamodb_policy" {
  name   = "CustomDynamoDBPolicy"
  role   = aws_iam_role.github_oidc_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.terraform_lock.arn
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

variable "backend_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
}

variable "dynamodb_table" {
  description = "DynamoDB table for state locking"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in the format 'owner/repo'"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch to use for OIDC"
  type        = string
}

variable "environment" {
  description = "Environment for tagging resources"
  type        = string
}


terraform {
  backend "s3" {
    bucket         = var.backend_bucket
    key            = var.backend_key
    region         = var.backend_region
    dynamodb_table = var.dynamodb_table
    encrypt        = true
  }
}

/*
variable "backend_bucket" {
  description = "The name of the S3 bucket for Terraform state"
}

variable "backend_key" {
  description = "The key (path) for the Terraform state file in S3"
}

variable "backend_region" {
  description = "The AWS region where the S3 bucket is located"
}

variable "dynamodb_table" {
  description = "The name of the DynamoDB table for state locking"
}

*/

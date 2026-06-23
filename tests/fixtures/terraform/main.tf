# Sample Terraform project: API Gateway -> Lambda -> DynamoDB, plus an S3 bucket.
# Points at LocalStack so infrapeek shows the LocalStack badge.

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_use_path_style           = true
  skip_credentials_validation = true

  endpoints {
    apigateway = "http://localhost:4566"
    dynamodb   = "http://localhost:4566"
    lambda     = "http://localhost:4566"
    s3         = "http://localhost:4566"
  }
}

resource "aws_dynamodb_table" "orders_table" {
  name         = "orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_lambda_function" "process_order" {
  function_name = "process_order"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  filename      = "build/process_order.zip"

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders_table.name
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "orders-api"
  description = "Fronts the process_order lambda: ${aws_lambda_function.process_order.function_name}"
}

resource "aws_s3_bucket" "assets" {
  bucket = "my-app-assets"
}

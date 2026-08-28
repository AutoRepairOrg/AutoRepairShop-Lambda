terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

# Lambda Login (gera JWT)
resource "aws_lambda_function" "login" {
  function_name = "autorepair-login"
  role         = data.aws_iam_role.lab.arn
  handler      = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"
  runtime      = "dotnet8"
  timeout      = 30
  memory_size  = 512
  filename     = "login-placeholder.zip"

  environment {
    variables = {
      RDS_ENDPOINT = "autorepair-sqlserver.cflewrgiz7x4.us-east-1.rds.amazonaws.com"
      DB_USER      = "admin"
    }
  }
}

# Lambda Authorizer (valida JWT)
resource "aws_lambda_function" "authorizer" {
  function_name = "autorepair-authorizer"
  role         = data.aws_iam_role.lab.arn
  handler      = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"
  runtime      = "dotnet8"
  timeout      = 30
  memory_size  = 256
  filename     = "authorizer-placeholder.zip"
}

# API Gateway REST
resource "aws_api_gateway_rest_api" "autorepair_api" {
  name        = "autorepair-api"
  description = "Auto Repair Shop API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Resource /auth
resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "auth"
}

# Resource /auth/login
resource "aws_api_gateway_resource" "login" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "login"
}

# Method POST /auth/login
resource "aws_api_gateway_method" "login_post" {
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  resource_id   = aws_api_gateway_resource.login.id
  http_method   = "POST"
  authorization = "NONE"
}

# Integration Lambda Login
resource "aws_api_gateway_integration" "login_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.autorepair_api.id
  resource_id             = aws_api_gateway_resource.login.id
  http_method             = aws_api_gateway_method.login_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.login.invoke_arn
}

# Lambda Permission para API Gateway
resource "aws_lambda_permission" "apigw_login" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.autorepair_api.execution_arn}/*/*"
}

# Lambda Authorizer
resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name                   = "jwt-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.autorepair_api.id
  authorizer_uri         = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials = data.aws_iam_role.lab.arn
  type                   = "TOKEN"
  identity_source        = "method.request.header.Authorization"
}

# Deploy API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  
  depends_on = [
    aws_api_gateway_integration.login_lambda
  ]
}

# Stage
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  stage_name    = "prod"
}

# Outputs
output "api_gateway_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}"
}

output "login_endpoint" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/auth/login"
}

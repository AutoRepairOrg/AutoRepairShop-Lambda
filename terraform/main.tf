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

# ============================================================
# IAM ROLE EXISTENTE
# ============================================================
data "aws_iam_role" "lab" {
  name = "LabRole"
}

# IMPORTAÇÃO DOS RECURSOS EXISTENTES
import {
  to = aws_lambda_permission.apigw_login
  id = "autorepair-login/AllowAPIGatewayInvokeLogin"
}

import {
  to = aws_lambda_function.login
  id = "autorepair-login"
}

import {
  to = aws_lambda_function.authorizer
  id = "autorepair-authorizer"
}

# ============================================================
# SECURITY GROUPS
# ============================================================
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sqlserver-sg"
  description = "Allows Lambda to access SQL Server NLB"
  vpc_id      = "vpc-0b43ff5d466697448"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG ID do NLB: você pode criar ou usar o que o AWS definiu
resource "aws_security_group_rule" "allow_sql_nlb" {
  type                     = "ingress"
  from_port               = 1433
  to_port                 = 1433
  protocol                = "tcp"
  source_security_group_id = aws_security_group.lambda_sg.id
  security_group_id       = "sg-do-nlb-aqui" # Consulte via `aws elbv2 describe-load-balancers`
}

# ============================================================
# SECRETS MANAGER PARA DB
# ============================================================
resource "aws_secretsmanager_secret" "db_secret" {
  name        = "autorepair/rds-credentials"
  description = "SQL Server credentials for Lambda"
}

resource "aws_secretsmanager_secret_version" "db_secret_ver" {
  secret_id     = aws_secretsmanager_secret.db_secret.id
  secret_string = jsonencode({
    username = "admin"
    password = "S3cur3P@ssword"
  })
}

# ============================================================
# LAMBDA - LOGIN COM VPC + ENV VARS
# ============================================================
resource "aws_lambda_function" "login" {
  function_name = "autorepair-login"
  role          = data.aws_iam_role.lab.arn
  handler       = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"
  runtime       = "dotnet8"

  filename         = "../login-lambda.zip"
  source_code_hash = filebase64sha256("../login-lambda.zip")

  timeout     = 30
  memory_size = 512

  # Lambda dentro da mesma VPC do EKS
  vpc_config {
    subnet_ids         = ["subnet-0f866ddddc81bc1f7", "subnet-0a19b68a818ec3508"]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST        = "k8s-oficina-sqlserve-xxxxx.elb.us-east-1.amazonaws.com" # NLB DNS do kubectl get svc
      DB_PORT        = "1433"
      DB_SECRET_NAME = aws_secretsmanager_secret.db_secret.name
      JWT_SECRET_NAME = "autorepair/jwt-secret"
    }
  }
}

# ============================================================
# LAMBDA - AUTHORIZER
# ============================================================
resource "aws_lambda_function" "authorizer" {
  function_name    = "autorepair-authorizer"
  role             = data.aws_iam_role.lab.arn
  handler          = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"
  runtime          = "dotnet8"
  filename         = "../authorizer-lambda.zip"
  source_code_hash = filebase64sha256("../authorizer-lambda.zip")

  timeout     = 30
  memory_size = 256
}

# ============================================================
# API GATEWAY CONFIG
# ============================================================
resource "aws_api_gateway_rest_api" "autorepair_api" {
  name        = "autorepair-api"
  description = "Auto Repair Shop API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# /auth
resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "auth"
}

# /auth/login
resource "aws_api_gateway_resource" "login" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "login"
}

resource "aws_api_gateway_method" "login_post" {
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  resource_id   = aws_api_gateway_resource.login.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "login_lambda" {
  rest_api_id                = aws_api_gateway_rest_api.autorepair_api.id
  resource_id                = aws_api_gateway_resource.login.id
  http_method                = aws_api_gateway_method.login_post.http_method
  integration_http_method    = "POST"
  type                       = "AWS_PROXY"
  uri                        = aws_lambda_function.login.invoke_arn
}

resource "aws_lambda_permission" "apigw_login" {
  statement_id  = "AllowAPIGatewayInvokeLogin"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.autorepair_api.execution_arn}/*/*"
}

# Authorizer config
resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name                           = "jwt-authorizer"
  rest_api_id                   = aws_api_gateway_rest_api.autorepair_api.id
  authorizer_uri                = aws_lambda_function.authorizer.invoke_arn
  authorizer_credentials        = data.aws_iam_role.lab.arn
  type                          = "TOKEN"
  identity_source               = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 0
}

# /api + proxy
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "api_proxy" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "api_proxy_any" {
  rest_api_id    = aws_api_gateway_rest_api.autorepair_api.id
  resource_id    = aws_api_gateway_resource.api_proxy.id
  http_method    = "ANY"
  authorization  = "CUSTOM"
  authorizer_id  = aws_api_gateway_authorizer.jwt_authorizer.id
  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# Gateway -> NLB -> EKS API
resource "aws_api_gateway_integration" "api_proxy" {
  rest_api_id                = aws_api_gateway_rest_api.autorepair_api.id
  resource_id                = aws_api_gateway_resource.api_proxy.id
  http_method                = aws_api_gateway_method.api_proxy_any.http_method
  integration_http_method    = "ANY"
  type                       = "HTTP_PROXY"
  uri                        = "http://${var.api_nlb_dns}/api/{proxy}"
  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# Deploy + Stage
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  depends_on = [
    aws_api_gateway_integration.login_lambda,
    aws_api_gateway_integration.api_proxy
  ]

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.auth.id,
      aws_api_gateway_resource.login.id,
      aws_api_gateway_resource.api.id,
      aws_api_gateway_resource.api_proxy.id,
      aws_api_gateway_method.login_post.id,
      aws_api_gateway_method.api_proxy_any.id,
      aws_api_gateway_integration.login_lambda.id,
      aws_api_gateway_integration.api_proxy.id,
      aws_api_gateway_authorizer.jwt_authorizer.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  stage_name    = "prod"
}

# Outputs
output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "login_endpoint" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/auth/login"
}

output "api_endpoint" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/api"
}

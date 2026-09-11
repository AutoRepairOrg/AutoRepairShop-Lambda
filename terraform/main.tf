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

# ============================================================
# RECURSOS EXISTENTES
# ============================================================

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
# VPC / SECURITY GROUP EXISTENTE DA LAMBDA
# ============================================================

data "aws_security_group" "lambda_sg" {
  id = "sg-05e8ea27678cd52ea"
}

# ============================================================
# SQL SERVER NLB EXISTENTE
# ============================================================

data "aws_lb" "sql_nlb" {
  name = "k8s-oficina-sqlserve-5f2488afbf"
}

# ============================================================
# SECRETS MANAGER EXISTENTES
# ============================================================

data "aws_secretsmanager_secret" "db_secret" {
  name = "autorepair/rds-credentials"
}

data "aws_secretsmanager_secret" "jwt_secret" {
  name = "autorepair/jwt-secret"
}

# ============================================================
# PERMISSÃO DO NLB PARA A LAMBDA
# ============================================================
#
# O NLB possui mais de um Security Group.
# Criamos a permissão TCP 1433 para cada SG associado ao NLB,
# permitindo acesso vindo do Security Group da Lambda.
#
# OBS:
# Se alguma dessas regras já existir exatamente igual, o Terraform
# poderá informar que a regra já existe. Nesse caso, ela deverá ser
# importada para o state em vez de criada novamente.
# ============================================================

resource "aws_vpc_security_group_ingress_rule" "lambda_to_sql_nlb" {
  for_each = toset(data.aws_lb.sql_nlb.security_groups)

  security_group_id            = each.value
  referenced_security_group_id = data.aws_security_group.lambda_sg.id

  ip_protocol = "tcp"
  from_port   = 1433
  to_port     = 1433

  description = "Allow Login Lambda to access SQL Server NLB"
}

# ============================================================
# LAMBDA - LOGIN
# ============================================================

resource "aws_lambda_function" "login" {
  function_name = "autorepair-login"

  role    = data.aws_iam_role.lab.arn
  runtime = "dotnet8"

  handler = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"

  filename         = "../login-lambda.zip"
  source_code_hash = filebase64sha256("../login-lambda.zip")

  timeout     = 30
  memory_size = 512

  # Lambda dentro da mesma VPC do EKS
  vpc_config {
    subnet_ids = [
      "subnet-0f866ddddc81bc1f7",
      "subnet-0a19b68a818ec3508"
    ]

    security_group_ids = [
      data.aws_security_group.lambda_sg.id
    ]
  }

  environment {
    variables = {
      DB_HOST         = data.aws_lb.sql_nlb.dns_name
      DB_PORT         = "1433"
      DB_SECRET_NAME  = data.aws_secretsmanager_secret.db_secret.name
      JWT_SECRET_NAME = data.aws_secretsmanager_secret.jwt_secret.name
    }
  }

  depends_on = [
    aws_vpc_security_group_ingress_rule.lambda_to_sql_nlb
  ]
}

# ============================================================
# LAMBDA - AUTHORIZER
# ============================================================

resource "aws_lambda_function" "authorizer" {
  function_name = "autorepair-authorizer"

  role    = data.aws_iam_role.lab.arn
  runtime = "dotnet8"

  handler = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"

  filename         = "../authorizer-lambda.zip"
  source_code_hash = filebase64sha256("../authorizer-lambda.zip")

  timeout     = 30
  memory_size = 256
}

# ============================================================
# API GATEWAY
# ============================================================

resource "aws_api_gateway_rest_api" "autorepair_api" {
  name        = "autorepair-api"
  description = "Auto Repair Shop API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ============================================================
# /AUTH
# ============================================================

resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id

  path_part = "auth"
}

# ============================================================
# /AUTH/LOGIN
# ============================================================

resource "aws_api_gateway_resource" "login" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.auth.id

  path_part = "login"
}

resource "aws_api_gateway_method" "login_post" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  resource_id = aws_api_gateway_resource.login.id

  http_method = "POST"

  authorization = "NONE"
}

resource "aws_api_gateway_integration" "login_lambda" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  resource_id = aws_api_gateway_resource.login.id

  http_method             = aws_api_gateway_method.login_post.http_method
  integration_http_method = "POST"

  type = "AWS_PROXY"

  uri = aws_lambda_function.login.invoke_arn
}

resource "aws_lambda_permission" "apigw_login" {
  statement_id = "AllowAPIGatewayInvokeLogin"

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.autorepair_api.execution_arn}/*/*"
}

# ============================================================
# JWT AUTHORIZER
# ============================================================

resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name = "jwt-authorizer"

  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  authorizer_uri = aws_lambda_function.authorizer.invoke_arn

  authorizer_credentials = data.aws_iam_role.lab.arn

  type = "TOKEN"

  identity_source = "method.request.header.Authorization"

  authorizer_result_ttl_in_seconds = 0
}

# ============================================================
# /API
# ============================================================

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id

  path_part = "api"
}

# ============================================================
# /API/{proxy+}
# ============================================================

resource "aws_api_gateway_resource" "api_proxy" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.api.id

  path_part = "{proxy+}"
}

resource "aws_api_gateway_method" "api_proxy_any" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  resource_id = aws_api_gateway_resource.api_proxy.id

  http_method = "ANY"

  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

# ============================================================
# API GATEWAY -> API NLB -> EKS
# ============================================================

resource "aws_api_gateway_integration" "api_proxy" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  resource_id = aws_api_gateway_resource.api_proxy.id

  http_method             = aws_api_gateway_method.api_proxy_any.http_method
  integration_http_method = "ANY"

  type = "HTTP_PROXY"

  uri = "http://${var.api_nlb_dns}/api/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# ============================================================
# API GATEWAY DEPLOYMENT
# ============================================================

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

# ============================================================
# API GATEWAY STAGE
# ============================================================

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id

  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  stage_name = "prod"
}

# ============================================================
# OUTPUTS
# ============================================================

output "api_gateway_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "login_endpoint" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/auth/login"
}

output "api_endpoint" {
  value = "${aws_api_gateway_stage.prod.invoke_url}/api"
}

output "sql_nlb_dns" {
  value = data.aws_lb.sql_nlb.dns_name
}

output "lambda_security_group" {
  value = data.aws_security_group.lambda_sg.id
}

output "sql_nlb_security_groups" {
  value = data.aws_lb.sql_nlb.security_groups
}

output "db_secret_name" {
  value = data.aws_secretsmanager_secret.db_secret.name
}

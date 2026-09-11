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

# ============================================================
# LAMBDA - LOGIN
# ============================================================

resource "aws_lambda_function" "login" {
  function_name = "autorepair-login"

  role    = data.aws_iam_role.lab.arn
  handler = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"
  runtime = "dotnet8"

  timeout     = 30
  memory_size = 512

  filename         = "../login-lambda.zip"
  source_code_hash = filebase64sha256("../login-lambda.zip")

  environment {
    variables = {
      DB_USER = "admin"
      DB_PORT = "1433"
    }
  }
}

# ============================================================
# LAMBDA - AUTHORIZER
# ============================================================

resource "aws_lambda_function" "authorizer" {
  function_name = "autorepair-authorizer"

  role    = data.aws_iam_role.lab.arn
  handler = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"
  runtime = "dotnet8"

  timeout     = 30
  memory_size = 256

  filename         = "../authorizer-lambda.zip"
  source_code_hash = filebase64sha256("../authorizer-lambda.zip")
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
# /auth
# ============================================================

resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "auth"
}

# ============================================================
# /auth/login
# ============================================================

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
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  resource_id = aws_api_gateway_resource.login.id

  http_method             = aws_api_gateway_method.login_post.http_method
  integration_http_method = "POST"

  type = "AWS_PROXY"

  uri = aws_lambda_function.login.invoke_arn
}

resource "aws_lambda_permission" "apigw_login" {
  statement_id = "AllowAPIGatewayInvokeLogin"

  action = "lambda:InvokeFunction"

  function_name = aws_lambda_function.login.function_name

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.autorepair_api.execution_arn}/*/*"
}

# ============================================================
# LAMBDA AUTHORIZER
# ============================================================

resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name        = "jwt-authorizer"
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  authorizer_uri = aws_lambda_function.authorizer.invoke_arn

  authorizer_credentials = data.aws_iam_role.lab.arn

  type = "TOKEN"

  identity_source = "method.request.header.Authorization"

  authorizer_result_ttl_in_seconds = 0
}

# ============================================================
# /api
# ============================================================

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  parent_id = aws_api_gateway_rest_api.autorepair_api.root_resource_id

  path_part = "api"
}

# ============================================================
# /api/{proxy+}
# ============================================================

resource "aws_api_gateway_resource" "api_proxy" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  parent_id = aws_api_gateway_resource.api.id

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
# API GATEWAY -> NLB -> EKS API
# ============================================================

resource "aws_api_gateway_integration" "api_proxy" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  resource_id = aws_api_gateway_resource.api_proxy.id

  http_method = aws_api_gateway_method.api_proxy_any.http_method

  integration_http_method = "ANY"

  type = "HTTP_PROXY"

  uri = "http://${var.api_nlb_dns}/api/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# ============================================================
# DEPLOYMENT
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
# STAGE
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

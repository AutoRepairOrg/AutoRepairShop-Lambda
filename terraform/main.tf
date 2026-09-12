terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "autorepair-tfstate-784355837864"
    key    = "lambda/terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# DATA SOURCES
# ============================================================

data "aws_iam_role" "lab" {
  name = "LabRole"
}

# EKS Auto Mode / AWS LB Controller usa esta tag (não service.k8s.aws/stack)
data "aws_lb" "sql_nlb" {
  tags = {
    "service.eks.amazonaws.com/stack" = var.sql_nlb_stack
  }
}

data "aws_lb" "api_nlb" {
  tags = {
    "service.eks.amazonaws.com/stack" = var.api_nlb_stack
  }
}

data "aws_subnet" "lambda" {
  id = var.lambda_subnet_ids[0]
}

# ============================================================
# DB SECRET (para a Login Lambda montar a connection string)
# ============================================================

resource "aws_secretsmanager_secret" "db_secret" {
  name = "autorepair/rds-credentials"
}

resource "aws_secretsmanager_secret_version" "db_secret" {
  secret_id = aws_secretsmanager_secret.db_secret.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    dbname   = var.db_name
  })
}

# ============================================================
# JWT SECRET
# ============================================================

resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "autorepair/jwt-secret"
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id = aws_secretsmanager_secret.jwt_secret.id

  secret_string = jsonencode({
    key = var.jwt_secret_key
  })
}

# ============================================================
# LOGIN LAMBDA
# ============================================================

resource "aws_lambda_function" "login" {
  function_name = "autorepair-login"
  role          = data.aws_iam_role.lab.arn

  handler = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"
  runtime = "dotnet8"

  filename         = "${path.module}/../login-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../login-lambda.zip")

  timeout     = 30
  memory_size = 512

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [aws_security_group.login_lambda.id]
  }

  environment {
    variables = {
      DB_HOST         = data.aws_lb.sql_nlb.dns_name
      DB_PORT         = "1433"
      DB_SECRET_NAME  = aws_secretsmanager_secret.db_secret.name
      JWT_SECRET_NAME = aws_secretsmanager_secret.jwt_secret.name
    }
  }
}

# ============================================================
# AUTHORIZER LAMBDA
# ============================================================

resource "aws_lambda_function" "authorizer" {
  function_name = "autorepair-authorizer"
  role          = data.aws_iam_role.lab.arn

  handler = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"
  runtime = "dotnet8"

  filename         = "${path.module}/../authorizer-lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../authorizer-lambda.zip")

  timeout     = 30
  memory_size = 512

  environment {
    variables = {
      JWT_SECRET_NAME = aws_secretsmanager_secret.jwt_secret.name
    }
  }
}

# ============================================================
# SECURITY GROUP - LOGIN LAMBDA
# ============================================================

resource "aws_security_group" "login_lambda" {
  name        = "autorepair-login-lambda"
  description = "Security group for AutoRepair Login Lambda"
  vpc_id      = data.aws_subnet.lambda.vpc_id

  tags = {
    Name = "autorepair-login-lambda"
  }
}

resource "aws_vpc_security_group_egress_rule" "login_lambda_all" {
  security_group_id = aws_security_group.login_lambda.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ============================================================
# SECURITY GROUP - LAMBDA -> SQL NLB (quando o NLB tiver SG)
# ============================================================

resource "aws_vpc_security_group_ingress_rule" "lambda_to_sql_nlb" {
  for_each = toset(compact(try(tolist(data.aws_lb.sql_nlb.security_groups), [])))

  security_group_id            = each.value
  referenced_security_group_id = aws_security_group.login_lambda.id
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
}

# ============================================================
# API GATEWAY REST API
# ============================================================

resource "aws_api_gateway_rest_api" "autorepair_api" {
  name        = "autorepair-api"
  description = "AutoRepairShop API Gateway (Login + proxy para API no EKS)"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "auth" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_resource" "login" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.auth.id
  path_part   = "login"
}

resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_resource" "health" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id
  parent_id   = aws_api_gateway_rest_api.autorepair_api.root_resource_id
  path_part   = "health"
}

# ============================================================
# AUTHORIZER
# ============================================================

resource "aws_lambda_permission" "apigw_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.autorepair_api.execution_arn}/*"
}

resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name                             = "jwt-authorizer"
  rest_api_id                      = aws_api_gateway_rest_api.autorepair_api.id
  type                             = "TOKEN"
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300
  authorizer_uri                   = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.authorizer.arn}/invocations"

  depends_on = [aws_lambda_permission.apigw_authorizer]
}

# ============================================================
# POST /auth/login -> Login Lambda
# ============================================================

resource "aws_api_gateway_method" "login_post" {
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  resource_id   = aws_api_gateway_resource.login.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_lambda_permission" "apigw_login" {
  statement_id  = "AllowAPIGatewayInvokeLogin"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.autorepair_api.execution_arn}/*/POST/auth/login"
}

resource "aws_api_gateway_integration" "login" {
  rest_api_id             = aws_api_gateway_rest_api.autorepair_api.id
  resource_id             = aws_api_gateway_resource.login.id
  http_method             = aws_api_gateway_method.login_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.login.arn}/invocations"

  depends_on = [aws_lambda_permission.apigw_login]
}

# ============================================================
# ANY /api/{proxy+} -> API NLB (JWT protected)
# ============================================================

resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.jwt_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "api_proxy" {
  rest_api_id             = aws_api_gateway_rest_api.autorepair_api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_any.http_method
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"
  uri                     = "http://${data.aws_lb.api_nlb.dns_name}/api/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

# ============================================================
# GET /health -> API NLB (public)
# ============================================================

resource "aws_api_gateway_method" "health_get" {
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  resource_id   = aws_api_gateway_resource.health.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "health" {
  rest_api_id             = aws_api_gateway_rest_api.autorepair_api.id
  resource_id             = aws_api_gateway_resource.health.id
  http_method             = aws_api_gateway_method.health_get.http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  uri                     = "http://${data.aws_lb.api_nlb.dns_name}/health"
}

# ============================================================
# DEPLOYMENT + STAGE
# ============================================================

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.autorepair_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.login.id,
      aws_api_gateway_integration.api_proxy.id,
      aws_api_gateway_integration.health.id,
      aws_api_gateway_authorizer.jwt_authorizer.id,
      data.aws_lb.api_nlb.dns_name,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.login,
    aws_api_gateway_integration.api_proxy,
    aws_api_gateway_integration.health,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.autorepair_api.id
  deployment_id = aws_api_gateway_deployment.prod.id
  stage_name    = "prod"
}

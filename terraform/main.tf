```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.eks_cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"

    args = [
      "eks",
      "get-token",
      "--cluster-name",
      var.eks_cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "eks_cluster_name" {
  type    = string
  default = "autorepairshop-eks"
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

data "aws_security_group" "lambda_sg" {
  id = "sg-05e8ea27678cd52ea"
}

data "aws_eks_cluster" "eks" {
  name = var.eks_cluster_name
}

data "aws_lb" "sql_nlb" {
  name = "k8s-oficina-sqlserve-5453bc1983"
}

data "aws_lb" "api_nlb" {
  name = "k8s-oficina-apinlb-ee4883a0c4"
}

data "aws_secretsmanager_secret" "db_secret" {
  name = "autorepair/rds-credentials"
}

data "aws_secretsmanager_secret" "jwt_secret" {
  name = "autorepair/jwt-secret"
}

data "aws_api_gateway_rest_api" "autorepair_api" {
  name = "autorepair-api"
}

data "aws_api_gateway_resource" "root" {
  rest_api_id = data.aws_api_gateway_rest_api.autorepair_api.id
  path        = "/"
}

data "aws_api_gateway_resource" "auth" {
  rest_api_id = data.aws_api_gateway_rest_api.autorepair_api.id
  path        = "/auth"
}

data "aws_api_gateway_resource" "login" {
  rest_api_id = data.aws_api_gateway_rest_api.autorepair_api.id
  path        = "/auth/login"
}

data "aws_api_gateway_resource" "api" {
  rest_api_id = data.aws_api_gateway_rest_api.autorepair_api.id
  path        = "/api"
}

data "aws_api_gateway_resource" "proxy" {
  rest_api_id = data.aws_api_gateway_rest_api.autorepair_api.id
  path        = "/api/{proxy+}"
}

resource "aws_lambda_function" "login" {
  function_name = "autorepair-login"
  role          = data.aws_iam_role.lab.arn

  handler = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"
  runtime = "dotnet8"

  filename = "${path.module}/../login-lambda.zip"

  timeout     = 30
  memory_size = 512

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
}

resource "aws_lambda_function" "authorizer" {
  function_name = "autorepair-authorizer"
  role          = data.aws_iam_role.lab.arn

  handler = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"
  runtime = "dotnet8"

  filename = "${path.module}/../authorizer-lambda.zip"

  timeout     = 30
  memory_size = 512

  environment {
    variables = {
      JWT_SECRET_NAME = data.aws_secretsmanager_secret.jwt_secret.name
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "lambda_to_sql_nlb" {
  for_each = data.aws_lb.sql_nlb.security_groups

  security_group_id            = each.value
  referenced_security_group_id = data.aws_security_group.lambda_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
}

resource "aws_lambda_permission" "apigw_login" {
  statement_id  = "AllowAPIGatewayInvokeLogin"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.login.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${data.aws_api_gateway_rest_api.autorepair_api.execution_arn}/*/POST/auth/login"
}

resource "aws_lambda_permission" "apigw_authorizer" {
  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${data.aws_api_gateway_rest_api.autorepair_api.execution_arn}/*"
}

resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name                             = "jwt-authorizer"
  rest_api_id                      = data.aws_api_gateway_rest_api.autorepair_api.id
  type                             = "TOKEN"
  identity_source                  = "method.request.header.Authorization"
  authorizer_result_ttl_in_seconds = 300

  authorizer_uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.authorizer.arn}/invocations"

  depends_on = [
    aws_lambda_permission.apigw_authorizer
  ]
}

resource "aws_api_gateway_integration" "login" {
  rest_api_id             = data.aws_api_gateway_rest_api.autorepair_api.id
  resource_id             = data.aws_api_gateway_resource.login.id
  http_method             = "POST"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"

  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${aws_lambda_function.login.arn}/invocations"

  depends_on = [
    aws_lambda_permission.apigw_login
  ]
}

resource "aws_api_gateway_integration" "api_proxy" {
  rest_api_id             = data.aws_api_gateway_rest_api.autorepair_api.id
  resource_id             = data.aws_api_gateway_resource.proxy.id
  http_method             = "ANY"
  integration_http_method = "ANY"
  type                    = "HTTP_PROXY"

  uri = "http://${data.aws_lb.api_nlb.dns_name}/api/{proxy}"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

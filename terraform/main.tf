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

# Lambda para Login (CPF + JWT)
resource "aws_lambda_function" "login" {
  filename         = "login.zip"
  function_name    = "autorepair-login"
  role            = data.aws_iam_role.lab.arn
  handler         = "AutoRepairShop.Login::AutoRepairShop.Login.Function::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 30
  memory_size     = 512

  environment {
    variables = {
      DB_CONNECTION_STRING = "seu-connection-string"
    }
  }
}

# Lambda Authorizer
resource "aws_lambda_function" "authorizer" {
  filename         = "authorizer.zip"
  function_name    = "autorepair-authorizer"
  role            = data.aws_iam_role.lab.arn
  handler         = "AutoRepairShop.Authorizer::AutoRepairShop.Authorizer.Function::FunctionHandler"
  runtime         = "dotnet8"
  timeout         = 30
  memory_size     = 256
}

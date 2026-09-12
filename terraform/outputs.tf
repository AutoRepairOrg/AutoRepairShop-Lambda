output "api_gateway_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.autorepair_api.id
}

output "api_gateway_invoke_url" {
  description = "Base invoke URL (prod stage)"
  value       = "https://${aws_api_gateway_rest_api.autorepair_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}

output "login_url" {
  description = "Login endpoint"
  value       = "https://${aws_api_gateway_rest_api.autorepair_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/auth/login"
}

output "api_proxy_url" {
  description = "Protected API proxy base path"
  value       = "https://${aws_api_gateway_rest_api.autorepair_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/api/"
}

output "health_url" {
  description = "Public health endpoint via API Gateway"
  value       = "https://${aws_api_gateway_rest_api.autorepair_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}/health"
}

output "api_nlb_dns" {
  description = "Resolved API NLB DNS name"
  value       = data.aws_lb.api_nlb.dns_name
}

output "sql_nlb_dns" {
  description = "Resolved SQL NLB DNS name"
  value       = data.aws_lb.sql_nlb.dns_name
}

output "login_lambda_name" {
  value = aws_lambda_function.login.function_name
}

output "authorizer_lambda_name" {
  value = aws_lambda_function.authorizer.function_name
}

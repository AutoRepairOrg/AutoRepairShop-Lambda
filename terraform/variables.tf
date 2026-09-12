variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "eks_cluster_name" {
  type    = string
  default = "autorepairshop-eks"
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
}

variable "lambda_subnet_ids" {
  description = "Private subnets for Login Lambda (VPC access to SQL NLB)"
  type        = list(string)
  default = [
    "subnet-0f4ea75a68f34c307",
    "subnet-0818a4d05d5ac968c"
  ]
}

variable "lambda_security_group_id" {
  description = "Security group used by Login Lambda in the VPC"
  type        = string
  default     = "sg-05e8ea27678cd52e"
}

variable "api_nlb_stack" {
  description = "AWS LB Controller stack tag for the API NLB (namespace/service)"
  type        = string
  default     = "oficina/api-nlb"
}

variable "sql_nlb_stack" {
  description = "AWS LB Controller stack tag for the SQL NLB (namespace/service)"
  type        = string
  default     = "oficina/sqlserver-nlb"
}

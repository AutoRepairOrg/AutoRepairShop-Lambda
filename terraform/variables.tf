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

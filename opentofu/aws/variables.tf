variable "aws_region" {
  type        = string
  default     = "eu-south-2"
  description = "AWS Region for deployment"
}

variable "cluster_name" {
  type        = string
  default     = "prod-cloud-native-eks"
  description = "Name of the EKS cluster"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "VPC CIDR block"
}
variable "aws_region" {
  description = "AWS region where the network will be created."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Prefix used for AWS resource names and default tags."
  type        = string
  default     = "app"
}

variable "vpc_cidr" {
  description = "CIDR block used by the VPC. Subnet CIDRs must be inside this range."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets. One subnet is created for each entry."
  type        = list(string)

  default = [
    "10.0.1.0/24",
    "10.0.2.0/24"
  ]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets. One subnet is created for each entry."
  type        = list(string)

  default = [
    "10.0.101.0/24",
    "10.0.102.0/24"
  ]
}

variable "tags" {
  description = "Additional tags applied to all AWS resources through the provider."
  type        = map(string)
  default     = {}
}

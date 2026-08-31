output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets. Useful for public ALBs, bastion hosts, and other Internet-facing resources."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets. Useful for application EC2 instances, ASGs, ECS tasks, and internal resources."
  value       = aws_subnet.private[*].id
}

output "public_route_table_id" {
  description = "ID of the route table used by public subnets."
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "ID of the route table used by private subnets."
  value       = aws_route_table.private.id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway used by private subnets for outbound Internet access."
  value       = aws_nat_gateway.this.id
}

output "availability_zones" {
  description = "Availability Zones used by the public subnets."
  value       = aws_subnet.public[*].availability_zone
}

output "public_ip" {
  value       = tencentcloud_instance.k3s_node.public_ip
  description = "The public IP of the Tencent CVM instance (used for VPN peer and SSH)"
}

output "private_ip" {
  value       = tencentcloud_instance.k3s_node.private_ip
  description = "The internal private IP of the Tencent CVM instance inside the VPC"
}

output "vpc_id" {
  value       = tencentcloud_vpc.vpc.id
  description = "The ID of the created Tencent Cloud VPC"
}

output "subnet_id" {
  value       = tencentcloud_subnet.subnet.id
  description = "The ID of the created Tencent Cloud Subnet"
}

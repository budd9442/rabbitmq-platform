variable "tencentcloud_secret_id" {
  type        = string
  description = "Tencent Cloud API Secret ID"
  default     = ""
}

variable "tencentcloud_secret_key" {
  type        = string
  description = "Tencent Cloud API Secret Key"
  sensitive   = true
  default     = ""
}

variable "region" {
  type        = string
  description = "Tencent Cloud Region"
  default     = "ap-jakarta"
}

variable "availability_zone" {
  type        = string
  description = "Tencent Cloud Availability Zone"
  default     = "ap-jakarta-1"
}

variable "instance_type" {
  type        = string
  description = "CVM Instance Type (SA5.LARGE16 for Jakarta 4 vCPU, 16 GB RAM)"
  default     = "SA5.LARGE16"
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH Key for login access to the CVM"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR Block (Non-overlapping with Oracle's 10.0.0.0/16)"
  default     = "10.1.0.0/16"
}

variable "subnet_cidr" {
  type        = string
  description = "Subnet CIDR Block within the VPC"
  default     = "10.1.1.0/24"
}

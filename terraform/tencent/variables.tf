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
  default     = "ap-singapore"
}

variable "availability_zone" {
  type        = string
  description = "Tencent Cloud Availability Zone"
  default     = "ap-singapore-1"
}

variable "instance_type" {
  type        = string
  description = "CVM Instance Type (Recommended: 4 vCPU, 16 GB RAM, e.g. S5.MEDIUM4 or SA3.MEDIUM4)"
  default     = "S5.MEDIUM4"
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

data "tencentcloud_images" "ubuntu" {
  image_type       = ["PUBLIC_IMAGE"]
  os_name          = "ubuntu"
  image_name_regex = "Ubuntu Server 24.04"
}

resource "tencentcloud_vpc" "vpc" {
  name       = "rmq-dr-vpc"
  cidr_block = var.vpc_cidr
}

resource "tencentcloud_subnet" "subnet" {
  vpc_id            = tencentcloud_vpc.vpc.id
  availability_zone = var.availability_zone
  name              = "rmq-dr-subnet"
  cidr_block        = var.subnet_cidr
}

resource "tencentcloud_security_group" "sg" {
  name        = "rmq-dr-sg"
  description = "Security group for RabbitMQ DR cluster node"
}

resource "tencentcloud_security_group_rule" "ingress_wireguard" {
  security_group_id = tencentcloud_security_group.sg.id
  type              = "ingress"
  cidr_ip           = "0.0.0.0/0"
  ip_protocol       = "udp"
  port_range        = "51820"
  policy            = "accept"
  description       = "Allow WireGuard VPN tunnel handshakes"
}

resource "tencentcloud_security_group_rule" "ingress_ssh" {
  security_group_id = tencentcloud_security_group.sg.id
  type              = "ingress"
  cidr_ip           = "0.0.0.0/0"
  ip_protocol       = "tcp"
  port_range        = "22"
  policy            = "accept"
  description       = "Allow SSH management access"
}

resource "tencentcloud_security_group_rule" "ingress_http" {
  security_group_id = tencentcloud_security_group.sg.id
  type              = "ingress"
  cidr_ip           = "0.0.0.0/0"
  ip_protocol       = "tcp"
  port_range        = "80"
  policy            = "accept"
  description       = "Allow HTTP web ingress"
}

resource "tencentcloud_security_group_rule" "ingress_https" {
  security_group_id = tencentcloud_security_group.sg.id
  type              = "ingress"
  cidr_ip           = "0.0.0.0/0"
  ip_protocol       = "tcp"
  port_range        = "443"
  policy            = "accept"
  description       = "Allow HTTPS web ingress"
}

resource "tencentcloud_security_group_rule" "egress_all" {
  security_group_id = tencentcloud_security_group.sg.id
  type              = "egress"
  cidr_ip           = "0.0.0.0/0"
  ip_protocol       = "all"
  policy            = "accept"
  description       = "Allow all outbound traffic"
}

resource "tencentcloud_key_pair" "key" {
  key_name   = "rmq-dr-key"
  public_key = var.ssh_public_key
}

resource "tencentcloud_instance" "k3s_node" {
  instance_name              = "rmq-dr-k3s-host"
  availability_zone          = var.availability_zone
  image_id                   = data.tencentcloud_images.ubuntu.images.0.image_id
  instance_type              = var.instance_type
  system_disk_type           = "CLOUD_SSD"
  system_disk_size           = 50
  key_name                   = tencentcloud_key_pair.key.key_name
  
  vpc_id                     = tencentcloud_vpc.vpc.id
  subnet_id                  = tencentcloud_subnet.subnet.id
  
  allocate_public_ip         = true
  internet_max_bandwidth_out = 100
  
  security_groups            = [tencentcloud_security_group.sg.id]
  
  user_data = base64encode(<<-EOF
              #!/bin/bash
              set -e
              
              # Wait for internet connectivity
              until ping -c 1 8.8.8.8; do sleep 1; done
              
              # Install dependencies
              apt-get update && apt-get install -y curl iptables wireguard-tools
              
              # Bootstrap K3s in DR mode with non-overlapping subnets
              curl -sfL https://get.k3s.io | sh -s - \
                --cluster-cidr=10.245.0.0/16 \
                --service-cidr=10.97.0.0/16
              
              # Wait for kubectl to be ready
              until /usr/local/bin/kubectl get nodes; do sleep 2; done
              
              echo "K3s installation and setup successfully completed!"
              EOF
  )
  
  tags = {
    Environment = "DR"
    Project     = "RabbitMQ-Platform"
  }
}

# DR Promotion workflow policy
# Applied to the GitHub Actions JWT auth role

# RabbitMQ cluster credentials
path "secret/data/rabbitmq/oracle" {
  capabilities = ["read"]
}

path "secret/data/rabbitmq/tencent" {
  capabilities = ["read"]
}

# Name.com DNS API credentials
path "secret/data/namecom" {
  capabilities = ["read"]
}

# SSH keys for STONITH fencing
path "secret/data/ssh/oracle" {
  capabilities = ["read"]
}

path "secret/data/ssh/tencent" {
  capabilities = ["read"]
}

# Shovel AMQP URIs (for post-promotion shovel repoint)
path "secret/data/rabbitmq/shovel" {
  capabilities = ["read"]
}

# Slack alert webhook
path "secret/data/notifications/slack" {
  capabilities = ["read"]
}

# Allow reading PKI certs for mTLS calls
path "pki/issue/rabbitmq-role" {
  capabilities = ["create", "update"]
}

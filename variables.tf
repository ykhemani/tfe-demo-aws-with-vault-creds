variable aws_region {
  type          = string
  description   = "The AWS Region in which we are provisioning resources."
  default       = "us-west-2"
}

variable vault_skip_tls_verify {
  type          = bool
  description   = "Set this to true to disable verification of the Vault server's TLS certificate."
  default       = false
}

variable vault_addr {
  type          = string
  description   = "Vault Cluster Address."
}

variable vault_role_id {
  type          = string
  description   = "Role ID for AppRole auth"
}

variable vault_secret_id {
  type          = string
  description   = "Secret ID for AppRole auth"
}

variable vault_auth_path {
  type          = string
  description   = "The login path of the auth backend."
  default       = "auth/approle/login"
}

variable vault_aws_backend {
  type          = string
  description   = "The path to the AWS secret backend to read credentials from."
  default       = "aws"
}

variable vault_aws_role {
  type          = string
  description   = "The name of the AWS secret backend role to read credentials from."
}

variable instance_type {
  description   = "type of EC2 instance to provision."
  default       = "t2.micro"
}

variable name {
  description   = "Name tag"
  default       = "tfe-aws-demo"
}

variable ubuntu_os_filter {
  type          = string
  description   = "OS Search Filter"
  default       = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
}

variable hashistack_os_filter {
  type          = string
  description   = "OS Search Filter"
  default       = "hashistack-*"
}

variable volume_type {
  type          = string
  description   = "The type of volume. Can be standard, gp2, or io1"
  default       = "gp2"
}

variable owner {
  type          = string
  description   = "Label to identify owner, will be used for tagging resources that are provisioned."
}

variable root_volume_size {
  type          = number
  description   = "Root disk size in gigabytes (GB)."
  default       = 20
}

variable root_volume_encrypted {
  type          = bool
  description   = "Is the root volume encrypted"
  default       = false
}

#variable aws_kms_key_id {
#  type          = string
#  description   = "ARN for KMS Key for encrypting/decrypting root volume"
#  default       = ""
#}

variable  ssh_key_name {
  type          = string
  description   = "Name of existing SSH key."
}

terraform {
  required_version  = ">= 0.12.23"
}

provider "vault" {
  address           = var.vault_addr
  skip_tls_verify   = var.vault_skip_tls_verify
  #token            = var.vault_token
  auth_login {
    path            = var.vault_auth_path

    parameters      = {
      role_id       = var.vault_role_id
      secret_id     = var.vault_secret_id
    }
  }
}

data "vault_aws_access_credentials" "creds" {
  backend           = var.vault_aws_backend
  role              = var.vault_aws_role
}

provider "aws" {
  region            = var.aws_region
  access_key        = data.vault_aws_access_credentials.creds.access_key
  secret_key        = data.vault_aws_access_credentials.creds.secret_key
}

################################################################################
# let's find the latest Ubuntu 18.04 image
data "aws_ami" "ubuntu" {
  most_recent       = true

  filter {
    name            = "name"
    values          = [var.ubuntu_os_filter]
  }

  filter {
    name            = "virtualization-type"
    values          = ["hvm"]
  }

  owners            = ["099720109477"] # Canonical
}

################################################################################
# let's provision an ec2 instance
resource "aws_instance" "demo" {
  #ami               = data.aws_ami.hashistack.id
  ami               = data.aws_ami.ubuntu.id
  instance_type     = var.instance_type
  availability_zone = "${var.aws_region}a"
  key_name          = var.ssh_key_name

  root_block_device {
    volume_type     = var.volume_type
    encrypted       = var.root_volume_encrypted
    volume_size     = var.root_volume_size
    #kms_key_id     = var.aws_kms_key_id
  }

  tags = {
    Name            = var.name
    Owner           = var.owner
  }
}

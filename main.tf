terraform {
  required_version = "~> 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    http = {
      version = "~> 1.1"
    }
  }
  backend "s3" {
  }
}

data "http" "ifconfig" {
  url = "http://ipv4.icanhazip.com/"
}

locals {
  current-ip = chomp(data.http.ifconfig.body)
  allowed-cidr  = "${local.current-ip}/32"
  cloud-config = <<END
#cloud-config
${jsonencode({
  write_files = [
    {
      path        = "/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"
      permissions = "0644"
      owner       = "root:root"
      encoding    = "b64"
      content     = filebase64("${path.module}/amazon-cloudwatch-agent.json")
    },
  ]
})}
END
}

data "cloudinit_config" "init" {
  gzip          = false
  base64_encode = false

  # The CloudWatch Agent configuration file is passed to the EC2 instance via cloud-init.(cf. https://stackoverflow.com/a/62105461)
  # There is also a way to use the SSM parameter store to pass settings.（cf. https://jazz-twk.medium.com/cloudwatch-agent-on-ec2-with-terraform-8cf58e8736de）
  part {
    content_type = "text/cloud-config"
    filename     = "cloud-config.yaml"
    content      = local.cloud-config
  }

  # NOTE: terraform appy completes before the cloud-init process completes.
  # It can also wait for cloud-init to complete.(cf. https://zenn.dev/thr/articles/6ddf5d90b82657)
  part {
    content_type = "text/x-shellscript"
    filename     = "setup_amazon_cloudwatch_agent.sh"
    content  = file("${path.module}/setup_amazon_cloudwatch_agent.sh")
  }
}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
  assume_role {
    role_arn = "${var.assume_role}"
  }
}

resource "aws_vpc" "web_vpc" {
  cidr_block = "${var.vpc_cidr}"
}

resource "aws_subnet" "web_subnet" {
  vpc_id     = aws_vpc.web_vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = "${var.availability_zone}"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "web_igw" {
  vpc_id = aws_vpc.web_vpc.id
}

resource "aws_route_table" "web_rtb" {
  vpc_id = aws_vpc.web_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web_igw.id
  }
}

resource "aws_route_table_association" "web_rtb_assoc" {
  subnet_id      = aws_subnet.web_subnet.id
  route_table_id = aws_route_table.web_rtb.id
}

resource "aws_security_group" "web_sg" {
  name   = "web-server-sg"
  vpc_id = aws_vpc.web_vpc.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "in_http" {
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.web_sg.id}"
}

resource "aws_security_group_rule" "in_ssh" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["${local.allowed-cidr}"]
  security_group_id = "${aws_security_group.web_sg.id}"
}

resource "aws_key_pair" "ssh_key" {
  key_name = "ssh_key"
  public_key = file("./terraform-training.rsa.pub")
}

resource "aws_iam_role" "logger_role" {
  name = "logger"
  path = "/"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "cw-policy_attach" {
  role = aws_iam_role.logger_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_iam_instance_profile" "web_server_profile" {
  name = "web_server_profile"
  role = aws_iam_role.logger_role.name
}

resource "aws_instance" "web_server" {
  ami                    = "ami-0e2bf1ada70fd3f33"
  instance_type          = "${var.instance_type}"
  subnet_id              = aws_subnet.web_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  iam_instance_profile = aws_iam_instance_profile.web_server_profile.name
  key_name = "${aws_key_pair.ssh_key.key_name}"
  user_data = data.cloudinit_config.init.rendered
}

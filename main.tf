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

resource "aws_instance" "web_server" {
  ami                    = "ami-0bba69335379e17f8"
  instance_type          = "${var.instance_type}"
  subnet_id              = aws_subnet.web_subnet.id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name = "${aws_key_pair.ssh_key.key_name}"
  user_data              = <<EOF
#! /bin/bash
sudo yum install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd
EOF
}

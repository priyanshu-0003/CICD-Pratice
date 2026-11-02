# ---------- Network ----------
resource "aws_vpc" "dev" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "paaji-vpc"
  }
}

resource "aws_subnet" "test" {
  vpc_id     = aws_vpc.dev.id
  cidr_block = var.subnet_cidr

  tags = {
    Name = "paaji-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev.id
  tags   = { Name = "paaji-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "paaji-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.test.id
  route_table_id = aws_route_table.public.id
}

# ---------- Security group (no SSH, SSM is used instead) ----------
resource "aws_security_group" "web" {
  name        = "paaji-web-sg"
  description = "Allow HTTP"
  vpc_id      = aws_vpc.dev.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- IAM role so SSM can manage the instance ----------
resource "aws_iam_role" "ec2_ssm" {
  name = "paaji-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "paaji-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ---------- EC2 ----------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.test.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name
  associate_public_ip_address = true

  # Runs automatically once, on first boot
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y python3 python3-pip
    python3 --version > /home/ec2-user/python-version.txt
    pip3 --version >> /home/ec2-user/python-version.txt
  EOF

  tags = {
    Name = "paaji-ec2"
  }
}

output "instance_id" {
  value = aws_instance.web.id
}

output "public_ip" {
  value = aws_instance.web.public_ip
}
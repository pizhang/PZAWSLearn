terraform {
  # Assumes s3 bucket and dynamo DB table already set up
  backend "s3" {
    bucket         = "tf-state-509399591785-ap-southeast-2"
    key            = "02-asg-missingami/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-2"
}

data "aws_ami" "ubuntu" {
    most_recent = true
    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
        }
}

data "aws_vpc" "selected" {
  id = "vpc-0644f0ed39837c87a"
}

data "aws_subnet" "public1" {
  id = "subnet-01413e0a98924db46"
}

data "aws_subnet" "public2" {
  id = "subnet-04ffaef97ea077eb2"
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Tier = "public"
  }
}

# Step 1: Create EC2 instance with user_data to create index.html
resource "aws_instance" "web_v1" {
    ami = "ami-0f5d1713c9af4fe30"
    instance_type = "t2.micro"
    subnet_id = data.aws_subnet.public1.id
    user_data = <<-EOF
        #!/bin/bash
        sudo apt-get update -y
        sudo apt-get install apache2 -y
        sudo systemctl start apache2
        sudo systemctl enable apache2
        echo "Hello World from $(hostname -f)" > /var/www/html/index.html
        EOF
    tags = {
        Name = "web_v1"
    }
}

# Create AMI from the instance
#resource "aws_ami_from_instance" "web_ami_v1" {
#    name = "web_ami_v1"
#    source_instance_id = aws_instance.web_v1.id
#}

# Step 3: Create EC2 instance with updated user_data
resource "aws_instance" "web_v2" {
  ami           = "ami-0f5d1713c9af4fe30"
  instance_type = "t2.micro"
  subnet_id = data.aws_subnet.public1.id
  user_data     = <<-EOF
                  #!/bin/bash
                  sudo apt-get update -y
                  sudo apt-get install -y apache2
                  sudo systemctl start apache2
                  sudo systemctl enable apache2
                  echo "Hello World v2" | sudo tee /var/www/html/index.html
                  EOF
  tags = {
    Name = "web_v2"
  }
}

# Create AMI v2 from the new instance
resource "aws_ami_from_instance" "web_ami_v2" {
  name               = "web-ami-v2"
  source_instance_id = aws_instance.web_v2.id
}

# Security Group for EC2 instances (allows HTTP from ALB)
resource "aws_security_group" "instance_sg" {
  name        = "instance-sg"
  description = "Allow HTTP from ALB"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]  # Allow traffic from ALB SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Update Launch Template to include instance security group
# Issue is the default version stays with old version, where AMI is missing
# Option is to define latest in ASG
# version = aws_launch_template.web_lt.latest_version  # Use latest version
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-lt-"
  image_id      = aws_ami_from_instance.web_ami_v2.id
  instance_type = "t2.micro"
  
  # Add security group for instances
  vpc_security_group_ids = [aws_security_group.instance_sg.id]
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP traffic"
  vpc_id = data.aws_vpc.selected.id

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

# ALB
resource "aws_lb" "web_alb" {
    name = "web-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = data.aws_subnets.public.ids
}

# Target Group
resource "aws_lb_target_group" "web_tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
    name = "web_asg"
    launch_template {
        id = aws_launch_template.web_lt.id
    }
    vpc_zone_identifier = data.aws_subnets.public.ids
    target_group_arns = [aws_lb_target_group.web_tg.arn]
    health_check_type = "ELB"
    desired_capacity = 2
    min_size = 2
    max_size = 2
}

# ALB Listener
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_alb.arn
  port = 80
  protocol = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

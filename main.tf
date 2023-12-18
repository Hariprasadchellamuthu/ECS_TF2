provider "aws" {
  region = "ap-south-1"  # Replace with your AWS region
}

# Create VPC and Subnets (similar to your existing code)
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "VPC_Pro2"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_subnet" "subnet_b" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "ap-south-1b"
}

# Security Group (similar to your existing code)
resource "aws_security_group" "ecs_security_group" {
  name        = "ecs-security-group"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.my_vpc.id

  # Define your security group rules here
  # Example inbound rules (modify as needed)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Example outbound rules (modify as needed)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_execution_role_policy" {
  name   = "ecs_execution_role_policy"
  role   = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:TerminateInstances",
          # Add other EC2 related actions as necessary
        ],
        Resource = "*",
      },
    ],
  })
}

resource "aws_iam_role" "ecs_task_role" {
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name   = "ecs_task_role_policy"
  role   = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "iam:PassRole",
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DeleteRole",
          # Add other IAM related actions as necessary
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          # Add other security group related actions as necessary
        ],
        Resource = "*",
      },
    ],
  })
}

# ECS Cluster 1 with Python Application
resource "aws_ecs_cluster" "python_cluster" {
  name = "python-ecs-cluster"
}

resource "aws_launch_configuration" "python_launch_configuration" {
  name                 = "python-launch-config"
  image_id             = "ami-0aee0743bf2e81172"  # Replace with your AMI ID
  instance_type        = "t2.small"  # Adjust instance type as needed
  associate_public_ip_address = true

  # Other configurations for the launch configuration as needed
}

resource "aws_autoscaling_group" "python_autoscaling_group" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1

  launch_configuration = aws_launch_configuration.python_launch_configuration.id
  vpc_zone_identifier  = [aws_subnet.subnet_a.id]

  # Additional configurations as needed
}

resource "aws_ecs_task_definition" "python_task_definition" {
  family                   = "python-task-family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]

  cpu    = "512"
  memory = "1024"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "python-container"
      image = "amazonlinux:latest"
      cpu   = 512
      memory = 1024
      essential = true
      command = [
        "/bin/bash",
        "-c",
        "yum update -y && yum install -y python3.6"
      ]
    }
  ])
}

resource "aws_ecs_service" "python_ecs_service" {
  name            = "python-ecs-service"
  cluster         = aws_ecs_cluster.python_cluster.id
  task_definition = aws_ecs_task_definition.python_task_definition.arn
  launch_type     = "EC2"

  network_configuration {
    subnets = [aws_subnet.subnet_a.id]
    security_groups = [aws_security_group.ecs_security_group.id]
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_ecs_task_definition.python_task_definition]
}

# ECS Cluster 2 with Jenkins Application
resource "aws_ecs_cluster" "jenkins_cluster" {
  name = "jenkins-ecs-cluster"
}

resource "aws_launch_configuration" "jenkins_launch_configuration" {
  name                 = "jenkins-launch-config"
  image_id             = "ami-0aee0743bf2e81172"  # Replace with your AMI ID
  instance_type        = "t2.micro"  # Adjust instance type as needed
  associate_public_ip_address = true

  # Other configurations for the launch configuration as needed
}

resource "aws_autoscaling_group" "jenkins_autoscaling_group" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1

  launch_configuration = aws_launch_configuration.jenkins_launch_configuration.id
  vpc_zone_identifier  = [aws_subnet.subnet_b.id]

  # Additional configurations as needed
}

resource "aws_ecs_task_definition" "jenkins_task_definition" {
  family                   = "jenkins-task-family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["EC2"]

  cpu    = "512"
  memory = "1024"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = "jenkins-container"
      image = "jenkins/jenkins:lts"
      cpu   = 512
      memory = 1024
      essential = true
      portMappings = [
        {
          containerPort = 8080,
          hostPort      = 8080
        },
      ]
    }
  ])
}

resource "aws_ecs_service" "jenkins_ecs_service" {
  name            = "jenkins-ecs-service"
  cluster         = aws_ecs_cluster.jenkins_cluster.id
  task_definition = aws_ecs_task_definition.jenkins_task_definition.arn
  launch_type     = "EC2"

  network_configuration {
    subnets = [aws_subnet.subnet_b.id]
    security_groups = [aws_security_group.ecs_security_group.id]
  }

  deployment_controller {
    type = "ECS"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_ecs_task_definition.jenkins_task_definition]
}

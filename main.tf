provider "aws" {
  region = "ap-south-1"  
}

# Create VPC and Subnets 
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

# Create Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create Route Table
resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
}

# Associate Route Table with Subnets
resource "aws_route_table_association" "subnet_a_association" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.my_route_table.id
}

resource "aws_route_table_association" "subnet_b_association" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.my_route_table.id
}

# Security Group 
resource "aws_security_group" "ecs_security_group" {
  name        = "ecs-security-group"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.my_vpc.id

  
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}


resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       = aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_agent" {
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}

# ECS Cluster 1 with Python Application
resource "aws_ecs_cluster" "python_cluster" {
  name = "python-ecs-cluster"
}

resource "aws_launch_configuration" "python_launch_configuration" {
  name                 = "python-launch-config"
  image_id             = "ami-0aee0743bf2e81172" 
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
  instance_type        = "t2.small" 
  security_groups      = [aws_security_group.ecs_security_group.id]
  user_data = <<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=python_cluster >> /etc/ecs/ecs.config
    yum install -y ecs-init
    start ecs
  EOF
  associate_public_ip_address = true  
}

resource "aws_autoscaling_group" "python_autoscaling_group" {
  desired_capacity          = 1
  max_size                  = 3
  min_size                  = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"

  launch_configuration = aws_launch_configuration.python_launch_configuration.name
  vpc_zone_identifier  = [aws_subnet.subnet_a.id]

  
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
  image_id             = "ami-0aee0743bf2e81172"
  iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
  instance_type        = "t2.micro"  
  security_groups      = [aws_security_group.ecs_security_group.id]
  user_data = <<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=jenkins_cluster >> /etc/ecs/ecs.config
    yum install -y ecs-init
    start ecs
  EOF
  associate_public_ip_address = true
}

resource "aws_autoscaling_group" "jenkins_autoscaling_group" {
  desired_capacity     = 1
  max_size             = 3
  min_size             = 1
  health_check_grace_period = 300
  health_check_type         = "EC2"

  launch_configuration = aws_launch_configuration.jenkins_launch_configuration.name
  vpc_zone_identifier  = [aws_subnet.subnet_b.id]

  
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

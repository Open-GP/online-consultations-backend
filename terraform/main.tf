# Create a new instance of the latest Ubuntu 14.04 on an
# t2.micro node with an AWS Tag naming it "HelloWorld"
provider "aws" {
  region = "eu-west-2"
}

terraform {
  backend "s3" {
    bucket = "opengp-infra"
    key    = "onlineconsultations/terraform.tfstate"
    region = "eu-west-2"
  }
}


#For now we only use the AWS ECS optimized ami <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html>
data "aws_ami" "amazon_linux_ecs" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
}

locals {
  name        = "onlineconsultations"
  environment = "demo"

  # This is the convention we use to know what belongs to each other
  ec2_resources_name = "${local.name}-${local.environment}"
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.name}_ecs_instance_profile"
  role = aws_iam_role.this.name
}

resource "aws_iam_role" "this" {
  name = "${local.name}_ecs_instance_role"
  path = "/ecs/"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ec2.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

data "template_file" "user_data" {
  template = file("templates/user-data.sh")

  vars = {
    cluster_name = local.name
  }
}
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.0"

  name = local.name

  cidr = "10.2.0.0/16"

  azs             = ["eu-west-2a", "eu-west-2b"]
  private_subnets = ["10.2.1.0/24", "10.2.2.0/24"]
  public_subnets  = ["10.2.11.0/24", "10.2.12.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway = false # this is faster, but should be "true" for real

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

module "this" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 3.0"

  name = local.ec2_resources_name

  # Launch configuration
  lc_name = local.ec2_resources_name

  image_id             = data.aws_ami.amazon_linux_ecs.id
  instance_type        = "t2.micro"
  iam_instance_profile = aws_iam_instance_profile.this.id
  user_data            = data.template_file.user_data.rendered

  # Auto scaling group
  asg_name                  = local.ec2_resources_name
  vpc_zone_identifier       = module.vpc.public_subnets
  health_check_type         = "EC2"
  min_size                  = 0
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Environment"
      value               = local.environment
      propagate_at_launch = true
    },
    {
      key                 = "Cluster"
      value               = local.name
      propagate_at_launch = true
    },
  ]
}

module "ecs" {
  source = "terraform-aws-modules/ecs/aws"
  name   = local.name
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_role" {
  role = aws_iam_role.this.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_ec2_cloudwatch_role" {
  role = aws_iam_role.this.id
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_ecs_task_definition" "onlineconsulations" {
  family = "onlineconsulations"

  container_definitions = data.template_file.task_definition.rendered
}

data "template_file" "task_definition" {
  template = file("task-definitions/service.json")

}

resource "aws_ecs_service" "onlineconsulations" {
  name = local.name
  cluster = module.ecs.this_ecs_cluster_id
  task_definition = aws_ecs_task_definition.onlineconsulations.arn

  desired_count = 1

  deployment_maximum_percent = 100
  deployment_minimum_healthy_percent = 0

  load_balancer {
    target_group_arn = module.alb.target_group_arns[0]
    container_name = "onlineconsultations"
    container_port = 8080
  }

}

resource "aws_cloudwatch_log_group" "onlineconsultations" {
  name = "/ecs/onlineconsultations"
}

module "alb" {
  source = "terraform-aws-modules/alb/aws"
  version = "~> 5.0"

  name = "onlineconsultations"

  load_balancer_type = "application"

  access_logs = {
    bucket = "opengp-load-balancer-logs"
  }

  vpc_id = module.vpc.vpc_id
  subnets = module.vpc.public_subnets
  security_groups = [aws_security_group.public_lb.id]
  target_groups = [
    {
      name = "onlineconsultations"
      backend_protocol = "HTTP"
      backend_port = 80
      health_check = {
        healthy_threshold = 2
        unhealthy_threshold = 7
        path = "/"
        matcher = "200,301,302"
      }
    }
  ]

  http_tcp_listeners = [
    {
      port = 80
      protocol = "HTTP"
      target_group_index = 0
    }
  ]


}

resource "aws_security_group" "public_lb" {
  name = "public_lb"
  description = "Allow public traffic to the lb"
  vpc_id = module.vpc.vpc_id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port = 80
    to_port = 80
    protocol = "tcp"
  }
  egress {
    from_port = 80
    to_port = 80
    security_groups = [module.vpc.default_security_group_id]
    protocol = "tcp"
  }
}



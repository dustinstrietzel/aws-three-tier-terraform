#Data Blocks
data "aws_availability_zones" "available" {}


#Network resources
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.projecttf.id

  tags = {
    Name = "Terraform_Project"
  }
}

resource "aws_vpc" "projecttf" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Terraform_Project"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "public-a"
  }
}
resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "public-b"
  }
}
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "private-a"
  }
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.projecttf.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "private-b"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.projecttf.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }


  tags = {
    Name = "public-rt"
  }
}
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.projecttf.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }

  tags = {
    Name = "private-a-rt"
  }
}
resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.projecttf.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }

  tags = {
    Name = "private-b-rt"
  }
}
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_a.id
}
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_eip" "nat_a" {
  domain = "vpc"

  tags = {
    Name = "nat-a"
  }
}
resource "aws_eip" "nat_b" {
  domain = "vpc"

  tags = {
    Name = "nat-b"
  }
}

resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.gw]


  tags = {
    Name = "gw NAT-a"
  }
}
resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.public_b.id
  depends_on    = [aws_internet_gateway.gw]


  tags = {
    Name = "gw NAT-b"
  }
}

# Storage

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.projecttf.id
  service_name = "com.amazonaws.us-east-1.s3"
  route_table_ids = [
    aws_route_table.private_a.id,
    aws_route_table.private_b.id,
  ]
  vpc_endpoint_type = "Gateway"
  tags = {
    Name = "s3-vpc-endpoint"
  }

}

#Security Groups
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "Load balancer: accepts HTTP from the internet"
  vpc_id      = aws_vpc.projecttf.id

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "Application tier: accepts traffic from the load balancer only"
  vpc_id      = aws_vpc.projecttf.id

  tags = {
    Name = "app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "db-sg"
  description = "Database tier: accepts PostgreSQL from the application tier only"
  vpc_id      = aws_vpc.projecttf.id

  tags = {
    Name = "db-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_in_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}
resource "aws_vpc_security_group_egress_rule" "alb_out_to_app" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}
resource "aws_vpc_security_group_ingress_rule" "app_in_from_alb" {
  security_group_id            = aws_security_group.app.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  ip_protocol                  = "tcp"
  to_port                      = 80
}
resource "aws_vpc_security_group_egress_rule" "app_out_all" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

}
resource "aws_vpc_security_group_ingress_rule" "db_in_from_app" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = 5432
  ip_protocol                  = "tcp"
  to_port                      = 5432
}

#Load Balancer
resource "aws_lb" "main" {
  name               = "three-tier-app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = false


  tags = {
    Name = "three-tier-app-lb"
  }
}
resource "aws_lb_target_group" "app" {
  name     = "three-tier-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.projecttf.id
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
resource "aws_launch_template" "app" {
  name                   = "three-tier-app-lt"
  image_id               = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
  user_data = base64encode(<<-EOF
#!/bin/bash
set -e
dnf install -y httpd
systemctl enable --now httpd
echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
EOF
  )
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "three-tier-app-instance"
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "three-tier-app-asg"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  target_group_arns   = [aws_lb_target_group.app.arn]
}

resource "aws_db_subnet_group" "three-tier-app-db-subnets" {
  name       = "three-tier-app-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = {
    Name = "Main DB subnet group"
  }
}

resource "aws_db_instance" "three_tier_app_db" {
  allocated_storage      = 20
  db_name                = "appdb"
  identifier             = "three-tier-app-db"
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  username               = "appadmin"
  password               = var.db_password
  vpc_security_group_ids = [aws_security_group.db.id]
  multi_az               = true
  publicly_accessible    = false
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.three-tier-app-db-subnets.name
}


resource "aws_s3_bucket" "three_tier_app" {
  bucket        = "dustin-three-tier-app-83286502"
  force_destroy = true

  tags = {
    Name = "three-tier-app"

  }
}
resource "aws_s3_bucket_public_access_block" "three_tier_app" {
  bucket = aws_s3_bucket.three_tier_app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "app" {
  name = "three-tier-app-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "s3_uploads" {
  name = "three-tier-app-s3-uploads"
  role = aws_iam_role.app.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
      ]
      Resource = "${aws_s3_bucket.three_tier_app.arn}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "three-tier-app-instance-profile"
  role = aws_iam_role.app.name
}

#Cloudwatch

resource "aws_sns_topic" "three-tier-app-alerts" {
  name = "three-tier-app-alerts"
}

resource "aws_sns_topic_subscription" "user_updates_to_email" {
  topic_arn = aws_sns_topic.three-tier-app-alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "three-tier-elb-alarm" {
  alarm_name          = "three-tier-elb-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
  alarm_description = "This metric monitors the number of unhealthy hosts in the Application ELB"
  alarm_actions     = [aws_sns_topic.three-tier-app-alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "three-tier-rds-alarm" {
  alarm_name          = "three-tier-rds-alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 4 * 1024 * 1024 * 1024
  dimensions = {
    DBInstanceIdentifier = aws_db_instance.three_tier_app_db.identifier
  }
  alarm_description = "This metric monitors the free storage space in the RDS instance"
  alarm_actions     = [aws_sns_topic.three-tier-app-alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "three-tier-elb-5xx-alarm" {
  alarm_name          = "three-tier-elb-5xx-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
  }
  alarm_description = "This metric monitors the number of 5XX errors in the Application ELB"
  alarm_actions     = [aws_sns_topic.three-tier-app-alerts.arn]
}


#Budget

resource "aws_budgets_budget" "three-tier-app-budget" {
  name         = "three-tier-app-budget"
  budget_type  = "COST"
  limit_amount = "20"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "FORECASTED"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.alert_email]
  }
}


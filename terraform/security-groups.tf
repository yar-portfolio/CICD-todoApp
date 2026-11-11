resource "aws_security_group" "ansible_controller" {
  name        = "ansible-controller-sg"
  description = "Access to the Ansible Controller"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ansible-controller-sg"
  }
}

resource "aws_security_group" "jenkins_controller" {
  name        = "jenkins-controller-sg"
  description = "Access to the Jenkins Controller"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-controller-sg"
  }
}

resource "aws_security_group" "jenkins_agent" {
  name        = "jenkins-agent-sg"
  description = "Access to the Jenkins Agent"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jenkins-agent-sg"
  }
}

resource "aws_security_group" "sonarqube" {
  name        = "sonarqube-sg"
  description = "Access to SonarQube"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sonarqube-sg"
  }
}

resource "aws_security_group" "alb" {
  name        = "todo-alb-sg"
  description = "Public HTTP access to the Todo application load balancer"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "todo-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name        = "todo-ecs-sg"
  description = "Application traffic from the load balancer to ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "todo-ecs-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ansible_ssh_from_admin" {
  security_group_id = aws_security_group.ansible_controller.id
  description       = "SSH from the administrator"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_controller_ssh_from_admin" {
  security_group_id = aws_security_group.jenkins_controller.id
  description       = "SSH from the administrator"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_controller_ssh_from_ansible" {
  security_group_id            = aws_security_group.jenkins_controller.id
  description                  = "SSH from the Ansible Controller"
  referenced_security_group_id = aws_security_group.ansible_controller.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_controller_http_from_admin" {
  security_group_id = aws_security_group.jenkins_controller.id
  description       = "Jenkins web interface from the administrator"
  cidr_ipv4         = var.admin_cidr
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_controller_http_from_agent" {
  security_group_id            = aws_security_group.jenkins_controller.id
  description                  = "Jenkins connection from the Jenkins Agent"
  referenced_security_group_id = aws_security_group.jenkins_agent.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_controller_http_from_sonarqube" {
  security_group_id            = aws_security_group.jenkins_controller.id
  description                  = "Quality Gate webhook from SonarQube"
  referenced_security_group_id = aws_security_group.sonarqube.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_agent_ssh_from_admin" {
  security_group_id = aws_security_group.jenkins_agent.id
  description       = "SSH from the administrator"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_agent_ssh_from_ansible" {
  security_group_id            = aws_security_group.jenkins_agent.id
  description                  = "SSH from the Ansible Controller"
  referenced_security_group_id = aws_security_group.ansible_controller.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_agent_ssh_from_jenkins" {
  security_group_id            = aws_security_group.jenkins_agent.id
  description                  = "SSH agent connection from the Jenkins Controller"
  referenced_security_group_id = aws_security_group.jenkins_controller.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sonarqube_ssh_from_admin" {
  security_group_id = aws_security_group.sonarqube.id
  description       = "SSH from the administrator"
  cidr_ipv4         = var.admin_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sonarqube_ssh_from_ansible" {
  security_group_id            = aws_security_group.sonarqube.id
  description                  = "SSH from the Ansible Controller"
  referenced_security_group_id = aws_security_group.ansible_controller.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sonarqube_http_from_admin" {
  security_group_id = aws_security_group.sonarqube.id
  description       = "SonarQube web interface from the administrator"
  cidr_ipv4         = var.admin_cidr
  from_port         = 9000
  to_port           = 9000
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sonarqube_http_from_jenkins_controller" {
  security_group_id            = aws_security_group.sonarqube.id
  description                  = "SonarQube access from the Jenkins Controller"
  referenced_security_group_id = aws_security_group.jenkins_controller.id
  from_port                    = 9000
  to_port                      = 9000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "sonarqube_http_from_jenkins_agent" {
  security_group_id            = aws_security_group.sonarqube.id
  description                  = "Code analysis from the Jenkins Agent"
  referenced_security_group_id = aws_security_group.jenkins_agent.id
  from_port                    = 9000
  to_port                      = 9000
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTP access"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_http_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  description                  = "Todo application traffic from the ALB"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}



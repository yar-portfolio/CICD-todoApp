resource "aws_instance" "jenkins_controller" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.jenkins_controller_instance_type
  key_name                    = var.key_name
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.jenkins_controller.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "jenkins-controller"
    Role = "JenkinsController"
  }
}

data "aws_iam_instance_profile" "jenkins" {
  name = "JenkinsInfraRole"
}

resource "aws_instance" "jenkins_agent" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.jenkins_agent_instance_type
  key_name                    = var.key_name
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.jenkins_agent.id]
  associate_public_ip_address = true
  iam_instance_profile = data.aws_iam_instance_profile.jenkins.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "jenkins-agent"
    Role = "JenkinsAgent"
  }
}

resource "aws_instance" "ansible_controller" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.ansible_controller_instance_type
  key_name                    = var.key_name
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.ansible_controller.id]
  associate_public_ip_address = true
  user_data                   = templatefile("${path.module}/templates/ansible-controller-user-data.sh.tftpl", {})
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 12
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "ansible-controller"
    Role = "AnsibleController"
  }
}

resource "aws_instance" "sonarqube" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.sonarqube_instance_type
  key_name                    = var.key_name
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.sonarqube.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "sonarqube"
    Role = "SonarQube"
  }
}

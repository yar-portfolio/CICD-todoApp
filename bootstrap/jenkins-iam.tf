data "aws_iam_policy_document" "jenkins_trust" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "jenkins_agent" {
  name = "JenkinsInfraRole"
  assume_role_policy = data.aws_iam_policy_document.jenkins_trust.json
}

resource "aws_iam_instance_profile" "jenkins_agent" {
  name = "JenkinsInfraRole"
  role = aws_iam_role.jenkins_agent.name
}

resource "aws_iam_role_policy" "terraform_state" {
  name = "TerraformStateAccess"
  role = aws_iam_role.jenkins_agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.terraform_state.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/todoapp/terraform.tfstate"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${aws_s3_bucket.terraform_state.arn}/todoapp/terraform.tfstate.tflock"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_power_user" {
  role = aws_iam_role.jenkins_agent.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "jenkins_pass_ecs_role" {
  name = "JenkinsPassEcsRole"
  role = aws_iam_role.jenkins_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ecsTaskExecutionRole"

        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_iam_read" {
  role       = aws_iam_role.jenkins_agent.name
  policy_arn = "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
}

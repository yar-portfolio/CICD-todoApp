output "bucket_name" {
  value = aws_s3_bucket.terraform_state.bucket
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}


terraform {
  backend "s3" {
    bucket = "todoapp-tfstate-ea41d0ddb796e9651baed8ef24"
    key = "todoapp/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    use_lockfile = true
  }
}

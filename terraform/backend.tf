terraform {
  backend "s3" {
    bucket = "todoapp-tfstate-4a036d9132e3515472bdfe2ee7"
    key = "todoapp/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    use_lockfile = true
  }
}

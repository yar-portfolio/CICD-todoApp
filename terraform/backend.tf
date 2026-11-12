terraform {
  backend "s3" {
    bucket = ""
    key = "todoapp/terraform.tfstate"
    region = "us-east-1"
    encrypt = true
    use_lockfile = true
  }
}

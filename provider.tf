terraform {
  required_version = ">= 1.12"

  backend "s3" {
    bucket       = "dustin-terraform-state-83286502"
    key          = "three-tier-app/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }


  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
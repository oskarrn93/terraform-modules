# Uptime alarm for a site hosted anywhere: emails when https://example.com/
# goes down and when it's back up.

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Route 53 health check metrics only exist in us-east-1.
provider "aws" {
  region = "us-east-1"
}

module "website_monitoring" {
  source = "../.."

  domain_name = "example.com"
  emails      = ["me@example.com"]
}

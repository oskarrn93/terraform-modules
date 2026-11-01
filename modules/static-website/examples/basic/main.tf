# Two sites on one distribution: example.com with content uploaded by
# Terraform and a preview host, and example.se as a preview-only site whose
# content is deployed outside Terraform. Uptime alarms for the live site.

terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

# CloudFront certificates and Route 53 health check metrics live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_route53_zone" "this" {
  for_each = toset(["example.com", "example.se"])

  name = each.key
}

module "static_website" {
  source = "../.."

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name = "example"

  sites = {
    "example.com" = {
      zone_id      = aws_route53_zone.this["example.com"].zone_id
      content_path = "${path.module}/site"
      preview      = true
    }
    "example.se" = {
      zone_id = aws_route53_zone.this["example.se"].zone_id
      live    = false
      preview = true
    }
  }

  monitoring = {
    emails = ["me@example.com"]
  }
}

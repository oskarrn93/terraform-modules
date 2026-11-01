# Hostnames, DNS, certificate, content and monitoring, against mocked AWS.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  name = "test"
  sites = {
    "example.com" = {
      zone_id      = "Z1"
      content_path = "./tests/fixtures/site"
      preview      = true
    }
    "example.se" = {
      zone_id = "Z2"
      live    = false
      preview = true
    }
  }
}

run "hostnames_and_dns" {
  command = plan

  assert {
    condition = aws_cloudfront_distribution.this.aliases == toset([
      "example.com", "www.example.com", "preview.example.com", "preview.example.se",
    ])
    error_message = "Unexpected aliases: ${jsonencode(aws_cloudfront_distribution.this.aliases)}"
  }

  assert {
    condition     = aws_route53_record.alias["preview.example.se"].zone_id == "Z2"
    error_message = "Records should be created in the site's zone"
  }

  assert {
    condition     = length(aws_route53_record.alias_ipv6) == 4
    error_message = "Every hostname should get an AAAA record"
  }

  assert {
    condition     = output.hostnames["www.example.com"] == "example.com/"
    error_message = "www. should share the apex prefix"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "test-sites"
    error_message = "Bucket name should be derived from name"
  }
}

run "certificate_covers_all_sites" {
  command = plan

  assert {
    condition     = aws_acm_certificate.this.domain_name == "example.com"
    error_message = "First domain should be the certificate's primary name"
  }

  assert {
    condition     = aws_acm_certificate.this.subject_alternative_names == toset(["*.example.com", "example.se", "*.example.se"])
    error_message = "Certificate should cover apex and wildcard of every site"
  }

  assert {
    condition     = toset(keys(aws_route53_record.certificate_validation)) == toset(["example.com", "example.se"])
    error_message = "One validation record per site"
  }
}

run "content_prefixed_by_domain" {
  command = plan

  assert {
    condition     = toset(keys(aws_s3_object.content)) == toset(["example.com/index.html", "example.com/css/style.css"])
    error_message = "Unexpected objects (dotfiles should be skipped): ${jsonencode(keys(aws_s3_object.content))}"
  }

  assert {
    condition     = aws_s3_object.content["example.com/css/style.css"].content_type == "text/css"
    error_message = "Content type should follow the extension"
  }
}

run "monitoring_off_by_default" {
  command = plan

  assert {
    condition     = length(module.monitoring) == 0
    error_message = "No monitoring unless enabled"
  }
}

run "monitoring_covers_live_sites" {
  command = plan

  variables {
    monitoring = { emails = ["a@example.com"] }
  }

  assert {
    condition     = toset(keys(module.monitoring)) == toset(["example.com"])
    error_message = "Only live sites should be monitored, not preview-only ones"
  }
}

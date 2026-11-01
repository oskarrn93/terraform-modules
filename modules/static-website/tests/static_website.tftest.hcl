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

run "security_headers" {
  command = plan

  assert {
    condition     = aws_cloudfront_response_headers_policy.security.security_headers_config[0].frame_options[0].frame_option == "DENY"
    error_message = "Pages should not be framed"
  }

  assert {
    condition = (
      aws_cloudfront_response_headers_policy.security.security_headers_config[0].strict_transport_security[0].access_control_max_age_sec == 63072000
      && !aws_cloudfront_response_headers_policy.security.security_headers_config[0].strict_transport_security[0].include_subdomains
    )
    error_message = "HSTS should last 2 years and leave out subdomains (the zones have subdomains that aren't ours)"
  }

  assert {
    condition     = aws_cloudfront_response_headers_policy.security.security_headers_config[0].referrer_policy[0].referrer_policy == "strict-origin-when-cross-origin"
    error_message = "Unexpected referrer policy"
  }

  assert {
    condition     = one([for h in aws_cloudfront_response_headers_policy.security.custom_headers_config[0].items : h.header]) == "Permissions-Policy"
    error_message = "Permissions-Policy should be the only custom header"
  }
}

# apply against the mocks, so the distribution can be checked against the
# (mocked) IDs and ARNs of the policy and functions it should use.
run "distribution_wiring" {
  command = apply

  # Mocks leave computed sets empty; the validation records need one entry per name.
  override_resource {
    target = aws_acm_certificate.this
    values = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/test"
      domain_validation_options = [
        for name in ["example.com", "*.example.com", "example.se", "*.example.se"] : {
          domain_name           = name
          resource_record_name  = "_x.${trimprefix(name, "*.")}."
          resource_record_type  = "CNAME"
          resource_record_value = "_y.acm-validations.aws."
        }
      ]
    }
  }

  # The provider checks these are ARNs; distinct ones show which function is where.
  override_resource {
    target = aws_cloudfront_function.rewrite
    values = { arn = "arn:aws:cloudfront::123456789012:function/test-sites-rewrite" }
  }

  override_resource {
    target = aws_cloudfront_function.response
    values = { arn = "arn:aws:cloudfront::123456789012:function/test-sites-response" }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].response_headers_policy_id == aws_cloudfront_response_headers_policy.security.id
    error_message = "The distribution should send the security headers"
  }

  assert {
    condition = {
      for f in aws_cloudfront_distribution.this.default_cache_behavior[0].function_association : f.event_type => f.function_arn
      } == {
      "viewer-request"  = aws_cloudfront_function.rewrite.arn
      "viewer-response" = aws_cloudfront_function.response.arn
    }
    error_message = "request.js should run on viewer requests and response.js on viewer responses"
  }

  assert {
    condition     = aws_cloudfront_function.rewrite.code == file("${path.module}/request.js") && aws_cloudfront_function.response.code == file("${path.module}/response.js")
    error_message = "Functions should deploy request.js and response.js"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "HTTP should redirect to HTTPS"
  }
}

run "price_class_defaults_to_100" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.price_class == "PriceClass_100"
    error_message = "Default price class should be PriceClass_100"
  }
}

run "price_class_can_be_changed" {
  command = plan

  variables {
    price_class = "PriceClass_All"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.price_class == "PriceClass_All"
    error_message = "price_class should reach the distribution"
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

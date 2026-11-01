# Several static sites in one private S3 bucket behind one CloudFront
# distribution. Each hostname's files live under a <hostname>/ prefix in the
# bucket (example.com/, preview.example.com/, ...), and request.js picks the
# prefix from the Host header.

locals {
  # Every hostname served, with the zone it lives in. www. hosts are only
  # there to be redirected to the apex by request.js.
  hostnames = merge([
    for domain, site in var.sites : merge(
      site.live ? {
        (domain)        = { zone_id = site.zone_id, prefix = domain }
        "www.${domain}" = { zone_id = site.zone_id, prefix = domain }
      } : {},
      site.preview ? {
        "preview.${domain}" = { zone_id = site.zone_id, prefix = "preview.${domain}" }
      } : {},
    )
  ]...)

  # One certificate for all sites; the wildcard covers www. and preview.
  certificate_names = flatten([for domain in sort(keys(var.sites)) : [domain, "*.${domain}"]])

  # Apex and wildcard share a validation record, so validate once per domain.
  validation_options = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }

  # Content uploaded by Terraform, for sites that set content_path.
  files = merge([
    for domain, site in var.sites : {
      for f in fileset(site.content_path, "**") : "${domain}/${f}" => "${site.content_path}/${f}"
      # Skip dotfiles and anything inside dot-directories (.git, .gitignore, ...).
      if length(regexall("(^|/)\\.", f)) == 0
    } if site.content_path != null
  ]...)

  content_types = {
    css   = "text/css"
    gif   = "image/gif"
    html  = "text/html"
    ico   = "image/x-icon"
    jpeg  = "image/jpeg"
    jpg   = "image/jpeg"
    js    = "text/javascript"
    json  = "application/json"
    pdf   = "application/pdf"
    png   = "image/png"
    svg   = "image/svg+xml"
    txt   = "text/plain"
    webp  = "image/webp"
    woff  = "font/woff"
    woff2 = "font/woff2"
    xml   = "application/xml"
  }
}

# --- Certificate -------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  provider = aws.us_east_1

  domain_name               = local.certificate_names[0]
  subject_alternative_names = slice(local.certificate_names, 1, length(local.certificate_names))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = var.sites

  allow_overwrite = true
  zone_id         = each.value.zone_id
  name            = local.validation_options[each.key].resource_record_name
  type            = local.validation_options[each.key].resource_record_type
  ttl             = 60
  records         = [local.validation_options[each.key].resource_record_value]
}

resource "aws_acm_certificate_validation" "this" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}

# --- Bucket ------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket = "${var.name}-sites"
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_object" "content" {
  for_each = local.files

  bucket       = aws_s3_bucket.this.id
  key          = each.key
  source       = each.value
  source_hash  = filemd5(each.value)
  content_type = lookup(local.content_types, lower(regex("[^.]*$", each.key)), "application/octet-stream")
}

# --- CloudFront --------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name}-sites"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "rewrite" {
  name    = "${var.name}-sites-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "www redirect, directory index and the per-hostname bucket prefix"
  publish = true
  code    = file("${path.module}/request.js")
}

resource "aws_cloudfront_function" "response" {
  name    = "${var.name}-sites-response"
  runtime = "cloudfront-js-2.0"
  comment = "X-Robots-Tag: noindex on preview. hosts"
  publish = true
  code    = file("${path.module}/response.js")
}

# No Content-Security-Policy: it depends on each site's content, so the pages
# set it themselves. HSTS leaves out subdomains on purpose: the zones can have
# other subdomains (mail., calendar., ...) that aren't ours to force onto HTTPS.
resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${var.name}-sites-security-headers"
  comment = "HSTS, nosniff, frame, referrer and permissions policy"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000 # 2 years
      include_subdomains         = false
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), interest-cohort=()"
      override = true
    }
  }
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "this" {
  comment         = "${var.name} sites"
  enabled         = true
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.price_class
  aliases         = sort(keys(local.hostnames))

  origin {
    origin_id                = "sites"
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id           = "sites"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.response.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# --- DNS ---------------------------------------------------------------------

resource "aws_route53_record" "alias" {
  for_each = local.hostnames

  zone_id = each.value.zone_id
  name    = each.key
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_ipv6" {
  for_each = local.hostnames

  zone_id = each.value.zone_id
  name    = each.key
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# --- Monitoring --------------------------------------------------------------

module "monitoring" {
  source   = "../website-monitoring"
  for_each = var.monitoring == null ? {} : { for domain, site in var.sites : domain => site if site.live }

  # Health check metrics only exist in us-east-1.
  providers = {
    aws = aws.us_east_1
  }

  domain_name = each.key
  emails      = var.monitoring.emails
}

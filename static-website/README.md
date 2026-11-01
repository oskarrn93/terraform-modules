# static-website

Several static sites in one private S3 bucket behind one CloudFront distribution.

- **One bucket, one distribution:** each hostname's files live under a `<hostname>/` prefix in the
  bucket (`example.com/`, `preview.example.com/`), and a CloudFront Function picks the prefix from
  the `Host` header.
- **One certificate:** an ACM certificate in us-east-1 covers the apex and wildcard of every site,
  validated through Route 53.
- **DNS:** A and AAAA alias records for every hostname.
- **`www.` redirects** with a 301 to the apex, keeping the path and query string.
- **Directory URLs:** `/about/` serves `about/index.html`, and `/about` redirects to `/about/`
  (S3 behind Origin Access Control has no index documents).
- **Preview hosts:** `preview.<domain>` serves `preview.<domain>/` from the bucket and is sent with
  `X-Robots-Tag: noindex, nofollow`.
- **Security headers:** HSTS (2 years, without subdomains), `X-Content-Type-Options`,
  `X-Frame-Options: DENY`, `Referrer-Policy` and `Permissions-Policy`. No Content-Security-Policy:
  it depends on the content, so pages set it themselves.
- **Content:** uploaded by Terraform from `content_path`, or deployed outside Terraform (e.g.
  `aws s3 sync` to the `bucket` output) when it's left out.
- **Monitoring (optional):** an uptime alarm per live site through
  [`website-monitoring`](../website-monitoring).

## Usage

```hcl
module "static_website" {
  source = "git::https://github.com/oskarrn93/terraform-modules.git//static-website?ref=static-website/v1.0.0"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1 # certificate and health checks live in us-east-1
  }

  name = "example"

  sites = {
    "example.com" = {
      zone_id      = aws_route53_zone.example.zone_id
      content_path = "${path.root}/site" # optional: uploaded to example.com/ in the bucket
      preview      = true                # also serve preview.example.com
    }
  }

  monitoring = {
    emails = ["me@example.com"]
  }
}
```

See [`examples/basic`](examples/basic) for a complete configuration.

## Notes

- ACM allows 10 names per certificate by default and every site uses two, so more than 5 sites in
  one instance needs a quota increase.
- Files under `content_path` whose name or any parent directory starts with `.` are not uploaded.
- Content types come from the file extension; unknown extensions are served as
  `application/octet-stream`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |
| <a name="provider_aws.us_east_1"></a> [aws.us\_east\_1](#provider\_aws.us\_east\_1) | >= 5.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_monitoring"></a> [monitoring](#module\_monitoring) | ../website-monitoring | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |
| [aws_acm_certificate_validation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_cloudfront_distribution.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_function.response](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_function.rewrite](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudfront_origin_access_control.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_cloudfront_response_headers_policy.security](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_response_headers_policy) | resource |
| [aws_route53_record.alias](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.alias_ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.certificate_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_object.content](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_cloudfront_cache_policy.caching_optimized](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_name"></a> [name](#input\_name) | Name of the site group, used for the bucket (`<name>-sites`), distribution comment and functions. | `string` | n/a | yes |
| <a name="input_sites"></a> [sites](#input\_sites) | Sites served by the shared distribution, keyed by apex domain.<br/><br/>- `zone_id`: Route 53 hosted zone for the domain.<br/>- `content_path`: local directory uploaded to `<domain>/` in the bucket. Null (default) leaves the content to be deployed outside Terraform, e.g. by `aws s3 sync` in CI.<br/>- `live`: serve `<domain>` (from `<domain>/` in the bucket) and redirect `www.<domain>` to it.<br/>- `preview`: serve `preview.<domain>` (from `preview.<domain>/` in the bucket), never indexed. | <pre>map(object({<br/>    zone_id      = string<br/>    content_path = optional(string)<br/>    live         = optional(bool, true)<br/>    preview      = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| <a name="input_monitoring"></a> [monitoring](#input\_monitoring) | Uptime monitoring for every live site (see ../website-monitoring): emails these addresses when a site goes down and when it's back up. Null disables it. | <pre>object({<br/>    emails = list(string)<br/>  })</pre> | `null` | no |
| <a name="input_price_class"></a> [price\_class](#input\_price\_class) | CloudFront price class. | `string` | `"PriceClass_100"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket"></a> [bucket](#output\_bucket) | Bucket holding all sites, one `<hostname>/` prefix per hostname. |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | ARN of the bucket, e.g. for a deploy role's IAM policy. |
| <a name="output_distribution_arn"></a> [distribution\_arn](#output\_distribution\_arn) | CloudFront distribution ARN, e.g. for a deploy role's IAM policy. |
| <a name="output_distribution_domain_name"></a> [distribution\_domain\_name](#output\_distribution\_domain\_name) | CloudFront domain name (*.cloudfront.net). |
| <a name="output_distribution_id"></a> [distribution\_id](#output\_distribution\_id) | CloudFront distribution ID, e.g. for cache invalidations. |
| <a name="output_hostnames"></a> [hostnames](#output\_hostnames) | Hostname => S3 prefix it's served from (www. hosts only redirect). |
| <a name="output_monitoring"></a> [monitoring](#output\_monitoring) | Domain => health check ID, for each monitored site. |
<!-- END_TF_DOCS -->

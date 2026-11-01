output "bucket" {
  description = "Bucket holding all sites, one `<hostname>/` prefix per hostname."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket, e.g. for a deploy role's IAM policy."
  value       = aws_s3_bucket.this.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID, e.g. for cache invalidations."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN, e.g. for a deploy role's IAM policy."
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name (*.cloudfront.net)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hostnames" {
  description = "Hostname => S3 prefix it's served from (www. hosts only redirect)."
  value       = { for h, v in local.hostnames : h => "${v.prefix}/" }
}

output "monitoring" {
  description = "Domain => health check ID, for each monitored site."
  value       = { for d, m in module.monitoring : d => m.health_check_id }
}

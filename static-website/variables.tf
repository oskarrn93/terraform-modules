variable "name" {
  description = "Name of the site group, used for the bucket (`<name>-sites`), distribution comment and functions."
  type        = string
}

variable "sites" {
  description = <<-EOT
    Sites served by the shared distribution, keyed by apex domain.

    - `zone_id`: Route 53 hosted zone for the domain.
    - `content_path`: local directory uploaded to `<domain>/` in the bucket. Null (default) leaves the content to be deployed outside Terraform, e.g. by `aws s3 sync` in CI.
    - `live`: serve `<domain>` (from `<domain>/` in the bucket) and redirect `www.<domain>` to it.
    - `preview`: serve `preview.<domain>` (from `preview.<domain>/` in the bucket), never indexed.
  EOT
  type = map(object({
    zone_id      = string
    content_path = optional(string)
    live         = optional(bool, true)
    preview      = optional(bool, false)
  }))
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "monitoring" {
  description = "Uptime monitoring for every live site (see ../website-monitoring): emails these addresses when a site goes down and when it's back up. Null disables it."
  type = object({
    emails = list(string)
  })
  default = null
}

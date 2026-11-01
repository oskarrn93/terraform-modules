output "hostnames" {
  description = "Hostname => S3 prefix it's served from."
  value       = module.static_website.hostnames
}

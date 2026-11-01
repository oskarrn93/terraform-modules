output "health_check_id" {
  description = "Route 53 health check ID."
  value       = module.website_monitoring.health_check_id
}

output "health_check_id" {
  description = "Route 53 health check ID."
  value       = aws_route53_health_check.this.id
}

output "alarm_arn" {
  description = "CloudWatch alarm ARN."
  value       = aws_cloudwatch_metric_alarm.this.arn
}

output "topic_arn" {
  description = "SNS topic the alarm notifies; subscribe more endpoints to it if needed."
  value       = aws_sns_topic.this.arn
}

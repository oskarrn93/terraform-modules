# Uptime monitoring for one website: a Route 53 health check on https://<domain>/
# and an alarm that emails when it fails and when it recovers.
#
# Route 53 health check metrics only exist in us-east-1, so pass a us-east-1
# provider as `aws`.

locals {
  slug = replace(var.domain_name, ".", "-")
}

resource "aws_route53_health_check" "this" {
  fqdn              = var.domain_name
  type              = "HTTPS"
  port              = 443
  request_interval  = 30
  failure_threshold = 3
  enable_sni        = true

  tags = {
    Name = var.domain_name
  }
}

resource "aws_sns_topic" "this" {
  name = "healthcheck-${local.slug}"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.emails)

  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "this" {
  alarm_name        = "healthcheck-${local.slug}"
  alarm_description = "https://${var.domain_name}/ is not responding. Checked by Route 53 health check ${aws_route53_health_check.this.id}."

  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  dimensions = {
    HealthCheckId = aws_route53_health_check.this.id
  }

  # Email when it goes down and when it's back up.
  alarm_actions = [aws_sns_topic.this.arn]
  ok_actions    = [aws_sns_topic.this.arn]
}

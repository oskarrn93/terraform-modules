mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:healthcheck-example-com"
    }
  }
}

variables {
  domain_name = "example.com"
  emails      = ["a@example.com", "b@example.com"]
}

run "checks_the_domain_over_https" {
  command = plan

  assert {
    condition     = aws_route53_health_check.this.fqdn == "example.com" && aws_route53_health_check.this.type == "HTTPS"
    error_message = "Health check should hit https://<domain_name>"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this.alarm_name == "healthcheck-example-com" && aws_sns_topic.this.name == "healthcheck-example-com"
    error_message = "Alarm and topic should be named after the domain"
  }
}

run "emails_on_alarm_and_recovery" {
  command = apply

  assert {
    condition     = toset(aws_cloudwatch_metric_alarm.this.alarm_actions) == toset([aws_sns_topic.this.arn]) && toset(aws_cloudwatch_metric_alarm.this.ok_actions) == toset([aws_sns_topic.this.arn])
    error_message = "Alarm should notify the topic both when firing and when back to OK"
  }

  assert {
    condition     = toset(keys(aws_sns_topic_subscription.email)) == toset(["a@example.com", "b@example.com"])
    error_message = "One email subscription per address"
  }
}

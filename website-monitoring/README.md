# website-monitoring

Uptime monitoring for one website: a Route 53 health check on `https://<domain>/` and a CloudWatch
alarm that emails through SNS when the site goes down and again when it recovers.

- **Health check:** HTTPS on port 443 with SNI, every 30 seconds, unhealthy after 3 failures in a
  row, checked from several AWS regions.
- **Alarm:** fires when the health check is unhealthy for a minute, and notifies again on recovery.
- **Email:** one SNS email subscription per address. Each address must confirm the subscription
  email from AWS once before alarms reach it.

Works for any site reachable over HTTPS, wherever it's hosted. [`static-website`](../static-website)
uses it for its `monitoring` option.

## Usage

Route 53 health check metrics only exist in us-east-1, so pass a us-east-1 provider as `aws`:

```hcl
module "website_monitoring" {
  source = "git::https://github.com/oskarrn93/terraform-modules.git//website-monitoring?ref=website-monitoring/v1.0.0"

  providers = {
    aws = aws.us_east_1
  }

  domain_name = "example.com"
  emails      = ["me@example.com"]
}
```

See [`examples/basic`](examples/basic) for a complete configuration.

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

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_metric_alarm.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_route53_health_check.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_health_check) | resource |
| [aws_sns_topic.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_domain_name"></a> [domain\_name](#input\_domain\_name) | Domain checked over HTTPS, e.g. example.com. | `string` | n/a | yes |
| <a name="input_emails"></a> [emails](#input\_emails) | Addresses emailed when the site goes down and when it's back up. Each must confirm the subscription email from AWS once. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_arn"></a> [alarm\_arn](#output\_alarm\_arn) | CloudWatch alarm ARN. |
| <a name="output_health_check_id"></a> [health\_check\_id](#output\_health\_check\_id) | Route 53 health check ID. |
| <a name="output_topic_arn"></a> [topic\_arn](#output\_topic\_arn) | SNS topic the alarm notifies; subscribe more endpoints to it if needed. |
<!-- END_TF_DOCS -->

variable "domain_name" {
  description = "Domain checked over HTTPS, e.g. example.com."
  type        = string
}

variable "emails" {
  description = "Addresses emailed when the site goes down and when it's back up. Each must confirm the subscription email from AWS once."
  type        = list(string)
}

# Shared by every module: CI runs `tflint --recursive` from the repo root.

config {
  # Also lint the modules' own module calls (static-website -> website-monitoring).
  call_module_type = "local"
}

# Terraform language rules, at the strictest preset: documented variables and
# outputs, typed variables, required_version and provider constraints, naming, ...
plugin "terraform" {
  enabled = true
  preset  = "all"
}

# AWS rules: invalid instance types, deprecated arguments, invalid enums, ...
plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

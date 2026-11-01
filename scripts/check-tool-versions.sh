#!/usr/bin/env bash
# Fails if the installed terraform, tflint or terraform-docs differ from the
# pinned versions (the ones CI uses), so local checks and CI can't disagree:
#   .terraform-version  terraform, managed by tfenv (`tfenv install`)
#   .tool-versions      tflint and terraform-docs (`mise install` or asdf)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

installed() {
  case "$1" in
    terraform)      terraform version -json | sed -n 's/.*"terraform_version": *"\([^"]*\)".*/\1/p' ;;
    tflint)         tflint --version | sed -n 's/^TFLint version \([0-9.]*\).*/\1/p' ;;
    terraform-docs) terraform-docs --version | sed -n 's/^terraform-docs version v\{0,1\}\([0-9.]*\).*/\1/p' ;;
  esac
}

status=0
while read -r tool want file; do
  if ! command -v "$tool" >/dev/null; then
    echo "$tool is not installed (want $want, see $file)"
    status=1
    continue
  fi
  # tfenv's terraform shim follows .terraform-version, so it fails (instead of
  # reporting another version) when that version isn't installed yet.
  have=$(installed "$tool" 2>/dev/null || true)
  if [ -z "$have" ]; then
    echo "$tool $want (from $file) is not installed or doesn't run"
    status=1
  elif [ "$have" != "$want" ]; then
    echo "$tool $have is installed, but $file pins $want"
    status=1
  fi
done < <(
  echo "terraform $(cat .terraform-version) .terraform-version"
  awk 'NF && $1 !~ /^#/ { print $1, $2, ".tool-versions" }' .tool-versions
)

if [ "$status" -ne 0 ]; then
  echo "Install the pinned versions so local checks match CI: 'tfenv install' for terraform, 'mise install' for the rest."
fi
exit "$status"

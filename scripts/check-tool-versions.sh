#!/usr/bin/env bash
# Fails if the installed terraform, tflint or terraform-docs differ from the
# versions pinned in .tool-versions (the ones CI uses), so local checks and CI
# can't disagree. `mise install` (or asdf) installs exactly the pinned versions.
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
while read -r tool want; do
  [ -z "$tool" ] || [ "${tool#\#}" != "$tool" ] && continue
  if ! command -v "$tool" >/dev/null; then
    echo "$tool is not installed (want $want, see .tool-versions)"
    status=1
    continue
  fi
  have=$(installed "$tool")
  if [ "$have" != "$want" ]; then
    echo "$tool $have is installed, but .tool-versions pins $want"
    status=1
  fi
done < .tool-versions

if [ "$status" -ne 0 ]; then
  echo "Install the pinned versions, e.g. with 'mise install', so local checks match CI."
fi
exit "$status"

#!/usr/bin/env bash
# Deploy to AWS: preflight -> terraform plan -> confirm -> apply -> smoke test.
#
#   scripts/deploy.sh               plan, ask, apply, test
#   scripts/deploy.sh --plan-only   dry run: show the plan, change nothing
#   AUTO_APPROVE=true scripts/deploy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
PLAN_ONLY=false

case "${1:-}" in
  "") ;;
  --plan-only) PLAN_ONLY=true ;;
  -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
  *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
esac

log() { echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

for tool in terraform aws curl; do
  command -v "$tool" >/dev/null || die "'$tool' not installed (see README prerequisites)"
done

caller="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" \
  || die "AWS credentials not working. Run 'aws configure' or 'aws sso login'."
log "AWS identity: ${caller}"

cd "$TF_DIR"
terraform init -input=false
terraform validate
terraform plan -input=false -out=tfplan

if [[ "$PLAN_ONLY" == "true" ]]; then
  rm -f tfplan
  log "Dry run finished, nothing was changed."
  exit 0
fi

if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
  read -r -p "Apply this plan? [y/N] " answer
  if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    rm -f tfplan
    log "Aborted, nothing changed."
    exit 0
  fi
fi

terraform apply -input=false tfplan
rm -f tfplan

url="$(terraform output -raw service_url)"
log "Service URL: ${url}"
log "Admin shell: $(terraform output -raw ssm_session_command)"
log "Smoke test (first boot takes 1-2 minutes)"
"${REPO_ROOT}/scripts/smoke-test.sh" "$url"

#!/usr/bin/env bash
# =============================================================================
# RUNBOOK — STATE UNLOCK (manual, run as YOURSELF from Codespaces or a laptop)
#
# Use when a pipeline run was cancelled or crashed mid plan/apply/destroy and
# Terraform reports: "Error acquiring the state lock … state blob is already locked".
#
# Safety:
#   - Refuses to run while a deploy/destroy workflow is queued or in progress.
#   - Shows who holds the lock and since when, then asks you to type "unlock".
#   - Uses `terraform force-unlock` with the exact lock ID (never edits state).
#
# Deliberately NOT a GitHub workflow: breaking locks needs a human decision.
#
# Usage (from the repo root):
#   az login --use-device-code          # Entra sign-in; state has no storage keys
#   ./runbook/state-unlock.sh           # auto-detects the lock ID
#   ./runbook/state-unlock.sh <LOCK_ID> # or pass the ID from the error message
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$REPO_ROOT/infra/backend.hcl"
LOCK_ID="${1:-}"

# ---- Pre-flight -------------------------------------------------------------
for t in az terraform gh jq; do
  command -v "$t" >/dev/null || { echo "ERROR: '$t' not found (Codespaces has all of these)."; exit 1; }
done
az account show -o none 2>/dev/null || { echo "ERROR: not signed in. Run: az login --use-device-code"; exit 1; }
export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

# Read backend settings from the committed backend.hcl (single source of truth).
hcl() { sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"/\1/p" "$BACKEND"; }
SA=$(hcl storage_account_name); CONTAINER=$(hcl container_name); KEY=$(hcl key)
[[ -n "$SA" && -n "$CONTAINER" && -n "$KEY" ]] || { echo "ERROR: could not read $BACKEND"; exit 1; }

# ---- 1. Is a pipeline still running? (a live lock must NOT be broken) -------
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
if [[ -n "$REPO" ]]; then
  ACTIVE=$(gh run list -R "$REPO" --limit 20 --json workflowName,status,databaseId \
    --jq '[.[] | select((.workflowName=="deploy" or .workflowName=="destroy") and (.status=="in_progress" or .status=="queued" or .status=="waiting" or .status=="pending"))] | length')
  if [[ "$ACTIVE" != "0" ]]; then
    echo "STOP: $ACTIVE deploy/destroy run(s) still active — the lock is probably live."
    gh run list -R "$REPO" --limit 5
    exit 1
  fi
else
  echo "WARN: gh not signed in — cannot check for running pipelines. Check GitHub Actions yourself."
fi

# ---- 2. Inspect the lock -----------------------------------------------------
LEASE=$(az storage blob show --auth-mode login --account-name "$SA" -c "$CONTAINER" -n "$KEY" \
  --query properties.lease.state -o tsv)
if [[ "$LEASE" != "leased" ]]; then
  echo "State is not locked (lease state: $LEASE). Nothing to do."
  exit 0
fi

# The azurerm backend stores lock info as base64 JSON in blob metadata "terraformlockid".
INFO_B64=$(az storage blob metadata show --auth-mode login --account-name "$SA" -c "$CONTAINER" -n "$KEY" \
  --query terraformlockid -o tsv 2>/dev/null || true)
if [[ -n "$INFO_B64" && "$INFO_B64" != "None" ]]; then
  INFO=$(printf '%s' "$INFO_B64" | base64 -d)
  echo "Current lock:"
  printf '%s' "$INFO" | jq '{ID, Operation, Who, Version, Created}'
  DETECTED=$(printf '%s' "$INFO" | jq -r .ID)
  if [[ -z "$LOCK_ID" ]]; then
    LOCK_ID="$DETECTED"
  elif [[ "$LOCK_ID" != "$DETECTED" ]]; then
    echo "STOP: you passed $LOCK_ID but the current lock is $DETECTED (a newer run took it)."; exit 1
  fi
fi
[[ -n "$LOCK_ID" ]] || { echo "ERROR: no lock ID detected — pass it from the error message."; exit 1; }

# ---- 3. Confirm and unlock ---------------------------------------------------
read -r -p "Type 'unlock' to release lock $LOCK_ID: " ok; [[ "$ok" == "unlock" ]] || { echo "Aborted."; exit 1; }

cd "$REPO_ROOT/infra"
terraform init -input=false -backend-config=backend.hcl >/dev/null
terraform force-unlock -force "$LOCK_ID"

echo "Done. Next: re-run the workflow that failed (Actions → deploy or destroy)."

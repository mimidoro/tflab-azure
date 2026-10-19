#!/usr/bin/env bash
# =============================================================================
# FINAL STEP — FULL TEARDOWN (run from your laptop, from the repo root)
#
# Run the GitHub "destroy" workflow FIRST (removes Terraform-managed resources
# cleanly). This script then removes everything bootstrap created:
# lab RG, state storage (lock removed first), Entra app/SP, SQL admin group,
# budget, and GitHub variables/environment.
#
# DESTRUCTIVE and irreversible: Terraform state history is deleted.
# =============================================================================
set -euo pipefail

PREFIX="tflab"
STATE_RG="rg-${PREFIX}-tfstate"
LAB_RG="rg-${PREFIX}-ause"
APP_NAME="sp-${PREFIX}-github"
SQL_ADMIN_GROUP="grp-${PREFIX}-sql-admins"
GH_ENVIRONMENT="lab"

SUB_ID=$(az account show --query id -o tsv)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

echo "This deletes $LAB_RG, $STATE_RG (incl. Terraform state), $APP_NAME, $SQL_ADMIN_GROUP in subscription $SUB_ID."
read -r -p "Type 'teardown' to continue: " ok; [[ "$ok" == "teardown" ]] || exit 1

echo "==> Lab resource group"
az group delete -n "$LAB_RG" --yes --no-wait 2>/dev/null || true

echo "==> State storage (remove lock, then delete RG)"
az lock delete -n "lock-tfstate-nodelete" -g "$STATE_RG" \
  --resource "$(az storage account list -g "$STATE_RG" --query '[0].name' -o tsv)" \
  --resource-type Microsoft.Storage/storageAccounts 2>/dev/null || true
az group delete -n "$STATE_RG" --yes --no-wait 2>/dev/null || true

echo "==> Custom role (Web operation-status reader)"
POLL_ROLE="${PREFIX}-web-operation-reader"
az role assignment delete --role "$POLL_ROLE" --scope "/subscriptions/${SUB_ID}" 2>/dev/null || true
az role definition delete --name "$POLL_ROLE" --custom-role-only true 2>/dev/null || true

echo "==> Entra app registration + SQL admin group"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
[[ -n "$APP_ID" ]] && az ad app delete --id "$APP_ID"
GRP_OID=$(az ad group list --display-name "$SQL_ADMIN_GROUP" --query "[0].id" -o tsv)
[[ -n "$GRP_OID" ]] && az ad group delete -g "$GRP_OID"

echo "==> Budget"
az rest --method delete \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Consumption/budgets/budget-${PREFIX}?api-version=2023-05-01" 2>/dev/null || true

echo "==> GitHub variables + environment"
for v in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID LAB_RG; do gh variable delete "$v" -R "$REPO" 2>/dev/null || true; done
gh api -X DELETE "repos/${REPO}/environments/${GH_ENVIRONMENT}" 2>/dev/null || true

echo "Teardown requested. Resource group deletion continues in the background (check: az group list -o table)."

#!/usr/bin/env bash
# =============================================================================
# STEP 1 OF 6 — BOOTSTRAP (run ONCE, from your laptop, from the repo root)
#
# Creates everything Terraform needs BEFORE Terraform can run ("chicken & egg"):
#   1. Registers Azure resource providers
#   2. Remote state: storage account (Entra-only, versioned, soft-delete, locked)
#   3. Lab resource group (the ONLY scope the pipeline identity can change)
#   4. Entra ID app + service principal with GitHub OIDC federated credentials
#      (no client secret is ever created)
#   5. Least-privilege role assignments
#   6. Entra group used as the Azure SQL admin (you + pipeline identity)
#   7. Subscription budget alert (NZ$ guardrail)
#   8. Writes infra/backend.hcl + infra/bootstrap.auto.tfvars (commit both)
#   9. Sets GitHub repo variables + creates the "lab" environment
#
# Prereqs: az CLI (logged in: az login), gh CLI (logged in: gh auth login),
#          run inside your cloned GitHub repo. Idempotent: safe to re-run.
#
# Optional overrides (env vars):
#   ALERT_EMAIL   budget alert recipient   (default: your az login email)
#   BUDGET_AMOUNT monthly budget, billing currency (default: 10)
# =============================================================================
set -euo pipefail

# ---- Settings (deliberate defaults, not placeholders) -----------------------
PREFIX="tflab"
LOCATION="australiaeast"
STATE_RG="rg-${PREFIX}-tfstate"
LAB_RG="rg-${PREFIX}-ause"
STATE_CONTAINER="tfstate"
STATE_KEY="${PREFIX}.tfstate"
APP_NAME="sp-${PREFIX}-github"
SQL_ADMIN_GROUP="grp-${PREFIX}-sql-admins"
GH_ENVIRONMENT="lab"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-10}"

# ---- Context discovered from your logins ------------------------------------
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
ME_OID=$(az ad signed-in-user show --query id -o tsv)
ALERT_EMAIL="${ALERT_EMAIL:-$(az account show --query user.name -o tsv)}"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
SUFFIX=$(printf '%s' "$SUB_ID" | sha1sum | cut -c1-6)   # deterministic, unique per subscription
STATE_SA="st${PREFIX}${SUFFIX}"                          # <= 24 chars, lowercase

# Pre-flight: bootstrap sets repo variables + environments, which needs repo ADMIN.
# In Codespaces the built-in GITHUB_TOKEN lacks this — use your own gh login instead.
if [[ "$(gh api "repos/${REPO}" --jq .permissions.admin 2>/dev/null)" != "true" ]]; then
  echo "ERROR: gh is not authenticated with admin rights on ${REPO}."
  echo "Fix:   unset GITHUB_TOKEN && gh auth login -s workflow && gh auth setup-git   (then re-run)"
  exit 1
fi

echo "Subscription : $SUB_ID"
echo "GitHub repo  : $REPO"
echo "State SA     : $STATE_SA ($STATE_RG)"
echo "Lab RG       : $LAB_RG"
echo "Alert email  : $ALERT_EMAIL"
read -r -p "Proceed? [y/N] " ok; [[ "$ok" == "y" ]] || exit 1

retry() { local n=0; until "$@"; do n=$((n+1)); [[ $n -ge 10 ]] && return 1; echo "  retry $n (waiting for RBAC/Entra propagation)…"; sleep 15; done; }

# ---- 1. Resource providers ---------------------------------------------------
echo "==> Registering resource providers"
for ns in Microsoft.Storage Microsoft.Web Microsoft.Sql Microsoft.Consumption Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns" --wait >/dev/null
done

# ---- 2. Remote state storage -------------------------------------------------
echo "==> Remote state storage"
az group create -n "$STATE_RG" -l "$LOCATION" --tags workload=$PREFIX purpose=tfstate >/dev/null
if ! az storage account show -n "$STATE_SA" -g "$STATE_RG" >/dev/null 2>&1; then
  az storage account create -n "$STATE_SA" -g "$STATE_RG" -l "$LOCATION" \
    --sku Standard_LRS --kind StorageV2 --https-only true --min-tls-version TLS1_2 \
    --allow-blob-public-access false --allow-shared-key-access false \
    --tags workload=$PREFIX purpose=tfstate >/dev/null
fi
az storage account blob-service-properties update -n "$STATE_SA" -g "$STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 7 \
  --enable-container-delete-retention true --container-delete-retention-days 7 >/dev/null
SA_ID=$(az storage account show -n "$STATE_SA" -g "$STATE_RG" --query id -o tsv)

# You need data-plane access because shared keys are disabled
az role assignment create --assignee-object-id "$ME_OID" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" >/dev/null 2>&1 || true
retry az storage container create -n "$STATE_CONTAINER" --account-name "$STATE_SA" --auth-mode login >/dev/null
az lock create -n "lock-tfstate-nodelete" --lock-type CanNotDelete -g "$STATE_RG" \
  --resource "$STATE_SA" --resource-type Microsoft.Storage/storageAccounts >/dev/null

# ---- 3. Lab resource group ---------------------------------------------------
echo "==> Lab resource group"
az group create -n "$LAB_RG" -l "$LOCATION" --tags workload=$PREFIX env=lab >/dev/null
LAB_RG_ID=$(az group show -n "$LAB_RG" --query id -o tsv)

# ---- 4. Entra app + service principal + OIDC federation ----------------------
echo "==> Pipeline identity (OIDC, no secrets)"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [[ -z "$APP_ID" ]]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
fi
SP_OID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || az ad sp create --id "$APP_ID" --query id -o tsv)

add_fic() { # name subject
  if ! az ad app federated-credential list --id "$APP_ID" --query "[?name=='$1']" -o tsv | grep -q .; then
    az ad app federated-credential create --id "$APP_ID" --parameters "{
      \"name\": \"$1\", \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$2\", \"audiences\": [\"api://AzureADTokenExchange\"] }" >/dev/null
  fi
}
add_fic "gh-pull-request" "repo:${REPO}:pull_request"
add_fic "gh-main"         "repo:${REPO}:ref:refs/heads/main"
add_fic "gh-env-lab"      "repo:${REPO}:environment:${GH_ENVIRONMENT}"

# ---- 5. Least-privilege roles ------------------------------------------------
echo "==> Role assignments (least privilege)"
retry az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "$LAB_RG_ID" >/dev/null
retry az role assignment create --assignee-object-id "$SP_OID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "${SA_ID}/blobServices/default/containers/${STATE_CONTAINER}" >/dev/null

# ---- 6. SQL admin group ------------------------------------------------------
echo "==> SQL admin Entra group"
GRP_OID=$(az ad group list --display-name "$SQL_ADMIN_GROUP" --query "[0].id" -o tsv)
if [[ -z "$GRP_OID" ]]; then
  GRP_OID=$(az ad group create --display-name "$SQL_ADMIN_GROUP" --mail-nickname "$SQL_ADMIN_GROUP" --query id -o tsv)
fi
for m in "$ME_OID" "$SP_OID"; do
  [[ "$(az ad group member check -g "$GRP_OID" --member-id "$m" --query value -o tsv)" == "true" ]] || \
    retry az ad group member add -g "$GRP_OID" --member-id "$m"
done

# ---- 7. Budget guardrail (alerts only — does NOT stop spend) -----------------
echo "==> Subscription budget alert"
START=$(date -u +%Y-%m-01T00:00:00Z)
az rest --method put \
  --url "https://management.azure.com/subscriptions/${SUB_ID}/providers/Microsoft.Consumption/budgets/budget-${PREFIX}?api-version=2023-05-01" \
  --body "{
    \"properties\": {
      \"category\": \"Cost\", \"amount\": ${BUDGET_AMOUNT}, \"timeGrain\": \"Monthly\",
      \"timePeriod\": { \"startDate\": \"${START}\" },
      \"notifications\": {
        \"actual-gt-1pct\":   { \"enabled\": true, \"operator\": \"GreaterThan\", \"threshold\": 1,   \"thresholdType\": \"Actual\",     \"contactEmails\": [\"${ALERT_EMAIL}\"] },
        \"actual-gt-50pct\":  { \"enabled\": true, \"operator\": \"GreaterThan\", \"threshold\": 50,  \"thresholdType\": \"Actual\",     \"contactEmails\": [\"${ALERT_EMAIL}\"] },
        \"forecast-gt-100\":  { \"enabled\": true, \"operator\": \"GreaterThan\", \"threshold\": 100, \"thresholdType\": \"Forecasted\", \"contactEmails\": [\"${ALERT_EMAIL}\"] }
      } } }" >/dev/null

# ---- 8. Terraform config files (non-secret — commit them) --------------------
echo "==> Writing infra/backend.hcl and infra/bootstrap.auto.tfvars"
cat > infra/backend.hcl <<EOF
# Generated by bootstrap/00-bootstrap.sh — non-secret, commit this file.
resource_group_name  = "${STATE_RG}"
storage_account_name = "${STATE_SA}"
container_name       = "${STATE_CONTAINER}"
key                  = "${STATE_KEY}"
use_azuread_auth     = true
EOF
cat > infra/bootstrap.auto.tfvars <<EOF
# Generated by bootstrap/00-bootstrap.sh — non-secret, commit this file.
lab_rg_name               = "${LAB_RG}"
sql_admin_group_name      = "${SQL_ADMIN_GROUP}"
sql_admin_group_object_id = "${GRP_OID}"
EOF

# ---- 9. GitHub variables + environment --------------------------------------
echo "==> GitHub variables and '${GH_ENVIRONMENT}' environment"
gh variable set AZURE_CLIENT_ID       --body "$APP_ID"    -R "$REPO"
gh variable set AZURE_TENANT_ID       --body "$TENANT_ID" -R "$REPO"
gh variable set AZURE_SUBSCRIPTION_ID --body "$SUB_ID"    -R "$REPO"
gh variable set LAB_RG                --body "$LAB_RG"    -R "$REPO"
gh api -X PUT "repos/${REPO}/environments/${GH_ENVIRONMENT}" >/dev/null

echo
echo "Bootstrap complete. Next: git add infra/backend.hcl infra/bootstrap.auto.tfvars && commit (see PLAYBOOK.md Step 2)."

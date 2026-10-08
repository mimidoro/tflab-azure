#!/usr/bin/env bash
# Runs once when the dev container is created. Safe to re-run.
set -euo pipefail

echo "==> Installing go-sqlcmd (optional locally — the pipeline installs its own)"
install_sqlcmd() {
  # Preferred: signed Microsoft apt repo
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/microsoft-prod.gpg &&
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main" \
    | sudo tee /etc/apt/sources.list.d/microsoft-prod.list >/dev/null &&
  sudo apt-get update -qq && sudo apt-get install -y -qq sqlcmd && return 0
  # Fallback: official GitHub release
  local t; t=$(mktemp -d)
  curl -fsSL https://github.com/microsoft/go-sqlcmd/releases/latest/download/sqlcmd-linux-amd64.tar.bz2 | tar -xj -C "$t" &&
  sudo install "$(find "$t" -type f -name sqlcmd | head -1)" /usr/local/bin/sqlcmd
}
command -v sqlcmd >/dev/null 2>&1 || install_sqlcmd || echo "WARN: sqlcmd not installed — only needed for manual SQL checks."

echo "==> Restoring app dependencies"
(cd app/web && npm ci --no-audit --no-fund)
dotnet restore app/api/Api.csproj

echo "==> Tool versions"
az version --query '"azure-cli"' -o tsv | sed 's/^/az        /'
gh --version | head -1
terraform version | head -1
echo "dotnet    $(dotnet --version)"
echo "node      $(node --version)"
command -v sqlcmd >/dev/null && sqlcmd --version | head -1 || true

cat <<'MSG'

Dev container ready. Next (see PLAYBOOK.md, Step P):
  1. az login --use-device-code
  2. unset GITHUB_TOKEN && gh auth login -s workflow && gh auth setup-git   (Codespaces)
  3. bash bootstrap/00-bootstrap.sh
MSG

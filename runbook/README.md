# Runbook — manual operations

Break-glass procedures a **human** runs, as themselves, when the pipeline can't fix itself.
They are deliberately not GitHub workflows: each one needs a judgement call first.

| Procedure | When | Run |
|---|---|---|
| **State unlock** | `Error acquiring the state lock … state blob is already locked` after a cancelled or crashed run | `./runbook/state-unlock.sh [LOCK_ID]` |

## Where to run

**Azure Cloud Shell** (recommended). In the Azure portal click `>_` and choose **Bash**. You're already
signed in with MFA, so there's no device-code step for security defaults to block.
`az`, `terraform`, `gh`, `jq` and `git` are preinstalled.

```bash
git clone https://github.com/mimidoro/tflab-azure && cd tflab-azure
./runbook/state-unlock.sh
```

**GitHub Codespaces** works only if device-code sign-in is allowed in your tenant
(security defaults may block it — see the table below).

```bash
az login --use-device-code --tenant 18b498fe-e48e-4047-978b-e3b465f34b76   # no --scope needed
./runbook/state-unlock.sh       # auto-detects the lock; pass the ID to double-check
```

## Lab identifiers

`runbook/lab.env` holds the lab **tenant ID** and **subscription ID** (both non-secret).
The script selects the subscription with `az account set` and checks it belongs to that tenant.

| Symptom at login | Cause | Fix |
|---|---|---|
| "No subscriptions found" | Signed in with an account that has no role on the subscription (often a cached work account picked on the device-code page) | `az logout`; open the device-code link in a **private** browser window; sign in as the account that ran bootstrap |
| `AADSTS530035: Access has been blocked by security defaults` | Security defaults treat **device-code sign-in from a cloud IP** (Codespaces) as risky | Use **Azure Cloud Shell** (already signed in) or a normal browser `az login` on your laptop. Don't disable security defaults |
| "You don't have permission to access this resource" | Resource-scoped login (`--scope`) or wrong account | Drop `--scope`; check `az account show` shows the account you ran bootstrap with |

If you used a codespace, stop it afterwards (**Code → Codespaces → ⋯ → Stop**) to save free hours.

## State unlock — what the script checks

1. **No pipeline is running.** It refuses if a `deploy` or `destroy` run is queued or in progress, because that lock is live.
2. **The state is actually locked.** It shows who holds the lock, the operation and when it started.
3. **The lock ID matches.** If you pass an ID and a newer run has taken the lock, it stops.
4. **You confirm** by typing `unlock`, then it runs `terraform force-unlock` with that exact ID.

**Access needed:** Storage Blob Data Contributor on the state container (bootstrap grants this to you).

**Never** delete or edit `tflab.tfstate` to clear a lock. You lose the record of what exists.

## Prevention

- Don't cancel a workflow while `apply` or `destroy` is running.
- Pushes that only change `bootstrap/`, `runbook/` or Markdown files don't trigger a deploy.

## Glossary

- **State lock:** a lease on the state blob that stops two Terraform runs writing at once.
- **Lease:** Azure Blob Storage's exclusive write lock on a blob.
- **Entra ID:** Microsoft's identity service (formerly Azure AD).
- **Tenant:** an Entra ID directory; each subscription belongs to exactly one.

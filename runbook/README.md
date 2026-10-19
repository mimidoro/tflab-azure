# Runbook — manual operations

Break-glass procedures a **human** runs, as themselves, when the pipeline can't fix itself.
They are deliberately not GitHub workflows: each one needs a judgement call first.

| Procedure | When | Run |
|---|---|---|
| **State unlock** | `Error acquiring the state lock … state blob is already locked` after a cancelled or crashed run | `./runbook/state-unlock.sh [LOCK_ID]` |

## Where to run

**GitHub Codespaces** (recommended). On the repo page: **Code → Codespaces → Create codespace on main**.
The dev container already has `az`, `terraform`, `gh` and `jq`.

```bash
az login --use-device-code      # no --tenant or --scope: the script picks the lab subscription
./runbook/state-unlock.sh       # auto-detects the lock; pass the ID to double-check
```

## Lab identifiers

`runbook/lab.env` holds the lab **subscription ID** (non-secret). Scripts select it with
`az account set` and derive the tenant from it, so you never type either.

| Symptom at login | Cause | Fix |
|---|---|---|
| "No subscriptions found" | Signed in to a tenant that doesn't own the subscription | `az logout`, then `az login --use-device-code` **without** `--tenant` |
| "You don't have permission to access this resource" | Resource-scoped login (`--scope`) or wrong account | Drop `--scope`; check `az account show` shows the account you ran bootstrap with |

Stop the codespace afterwards (**Code → Codespaces → ⋯ → Stop**) to save free hours.

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

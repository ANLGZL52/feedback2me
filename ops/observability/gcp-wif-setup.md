# GCP Workload Identity Federation — Ops runtime collector (read-only)

Activates GitHub Actions → GCP Cloud Logging with **no static keys**. The
`ops-health` workflow mints a **short-lived** access token per run via GitHub
OIDC and a dedicated **read-only** service account. Trust is scoped to **this
repo on `main` only**.

- Project: `feedbacktome-79655` (number `16565078393`)
- Repo: `ANLGZL52/feedback2me` (immutable `repository_id = 1200751360`)
- Dedicated SA: `feedback2me-ops-log-reader` — role: **`roles/logging.viewer`** only
- No service-account keys. No GitHub secrets holding GCP credentials.

## One-time provisioning (run once, as the project owner)

> Requires `gcloud` authenticated as an owner of `feedbacktome-79655`
> (`gcloud auth login`). These are the **only** commands that create cloud
> resources; the workflow itself creates nothing.

```bash
PROJECT=feedbacktome-79655
PROJECT_NUMBER=16565078393
POOL=github-ops
PROVIDER=github-oidc
SA=feedback2me-ops-log-reader
REPO_ID=1200751360   # immutable GitHub repository_id for ANLGZL52/feedback2me

# 1) Required APIs (Cloud Logging already enabled by the aiSummary deploy).
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com --project "$PROJECT"

# 2) Dedicated least-privilege service account — read Cloud Logging ONLY.
gcloud iam service-accounts create "$SA" --project "$PROJECT" \
  --display-name="Feedback2Me Ops log reader (read-only)"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:${SA}@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/logging.viewer"

# 3) Workload Identity Pool + GitHub OIDC provider, trust scoped to THIS repo + main.
gcloud iam workload-identity-pools create "$POOL" --project "$PROJECT" \
  --location=global --display-name="GitHub Ops"
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --project "$PROJECT" --location=global --workload-identity-pool="$POOL" \
  --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository_id=='${REPO_ID}' && assertion.ref=='refs/heads/main'"

# 4) Let ONLY this repo (by immutable id) impersonate the read-only SA.
gcloud iam service-accounts add-iam-policy-binding \
  "${SA}@${PROJECT}.iam.gserviceaccount.com" --project "$PROJECT" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}/attribute.repository_id/${REPO_ID}"
```

## Set the two NON-secret repo variables (not secrets)

```bash
gh variable set GCP_WIF_PROVIDER --repo ANLGZL52/feedback2me \
  --body "projects/16565078393/locations/global/workloadIdentityPools/github-ops/providers/github-oidc"
gh variable set GCP_WIF_SERVICE_ACCOUNT --repo ANLGZL52/feedback2me \
  --body "feedback2me-ops-log-reader@feedbacktome-79655.iam.gserviceaccount.com"
```

The provider resource path and SA email are **identifiers, not credentials** —
repo variables (not secrets) are the correct place for them. Until both are set,
the workflow's `gcp_auth` step is skipped and the GCP collector reports
`NOT_CONFIGURED` (workflow stays green).

## Security properties
- Short-lived token only (`access_token_lifetime: 300s`), minted per run; never
  stored, never printed. Scope: `logging.read` only.
- Trust bound to `repository_id=1200751360` **and** `ref=refs/heads/main` — no
  forks, no other branches, no other repos, no org-wide federation.
- SA holds **only** `roles/logging.viewer`. No Owner/Editor/Viewer, no Secret
  Manager, no Firebase/Functions/Run/Storage/Artifact/SA-admin.
- `id-token: write` is the only added workflow permission.

## Remote proof
Because trust is `main`-only, a true end-to-end WIF proof runs only after this
PR merges to `main` (scheduled run or `workflow_dispatch` on `main`). See the PR
`REMOTE_WIF_PROOF: POST_MERGE_REQUIRED`.

## Rollback
- Remove the two repo variables → `gcp_auth` is skipped, collector →
  `NOT_CONFIGURED`; observability returns to Railway+Postgres only. No code revert
  needed.
- To fully tear down: delete the provider, pool, and SA; remove the
  `roles/logging.viewer` binding.

## Not done here
Scheduled collector is wired but **inactive until provisioning + variables are
set**. WIF remains **NOT CONFIGURED** until the owner runs the above. Overall
observability stays **PARTIAL** until a real `main` run proves the full chain.

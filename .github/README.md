# GitHub Actions & automation

## CI (`workflows/ci.yml`)

Runs on pull requests and pushes to `main`:

- **Backend:** RuboCop, Zeitwerk, Gitleaks, bundler-audit, Brakeman, RSpec (PostgreSQL + Redis service containers).
- **Frontend:** `npm ci`, `npm audit` (high+), ESLint, production build.
- **Docker:** Hadolint on `backend/Dockerfile`.
- **PRs only:** GitHub dependency review.

### Path gem `delta_exchange`

`backend/Gemfile` uses `gem "delta_exchange", path: "../../delta_exchange"`. On GitHub-hosted runners, set a **repository variable**:

| Variable | Example | Purpose |
|----------|---------|---------|
| `DELTA_EXCHANGE_REPOSITORY` | `your-org/delta_exchange` | Optional second checkout; CI symlinks it to `../delta_exchange` next to the workspace. |

If the variable is empty, CI fails fast with an error (same as the previous backend-local workflow).

### Branch protection

Recommended required checks:

- Backend — style & Zeitwerk
- Backend — security scans
- Backend — RSpec
- Frontend — lint & build
- Dockerfile (Hadolint)

## Deploy (`workflows/deploy.yml`)

Disabled until you set repository variable **`ENABLE_KAMAL_DEPLOY`** to the literal string `true`.

Then use **Actions → Deploy → Run workflow**, or push a version tag `v*`. Configure **Environments** `staging` and `production` with secrets expected by Kamal (at minimum `RAILS_MASTER_KEY` and `KAMAL_REGISTRY_PASSWORD` per `backend/config/deploy.yml`).

## Dependabot

Configured in `dependabot.yml` for Bundler (`/backend`), npm (`/frontend`), and GitHub Actions.

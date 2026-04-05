# GitHub Actions & automation

## CI (`workflows/ci.yml`)

Runs on pull requests and pushes to `main`:

- **Backend:** RuboCop, Zeitwerk, Gitleaks, bundler-audit, Brakeman, RSpec (PostgreSQL + Redis service containers).
- **Frontend:** `npm ci`, `npm audit` (high+), ESLint, production build.
- **Docker:** Hadolint on `backend/Dockerfile`.
- **PRs only:** GitHub dependency review.

Backend gems (`delta_exchange`, `ollama-client`, etc.) are declared in `backend/Gemfile` and resolved from **RubyGems** only — no path gems and no extra checkout steps in CI.

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

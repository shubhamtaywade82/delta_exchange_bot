# GitHub Actions & automation

## CI (`workflows/ci.yml`)

Runs on pull requests and pushes to `main`:

- **Backend:** RuboCop, Zeitwerk, Gitleaks, bundler-audit, Brakeman, RSpec (PostgreSQL + Redis service containers).
- **Frontend:** `npm ci`, `npm audit` (high+), ESLint, production build.
- **Docker:** Hadolint on `backend/Dockerfile`.
- **PRs only:** GitHub dependency review.

### `delta_exchange` gem

`backend/Gemfile` loads **`delta_exchange` from RubyGems** by default (`Gemfile.lock` has no `PATH` entry for it). CI does **not** require any extra checkout.

If you switch the Gemfile to **`gem "delta_exchange", path: "../../delta_exchange"`**, set a **repository variable** so CI can check out and symlink the gem:

| Variable | Example | Purpose |
|----------|---------|---------|
| `DELTA_EXCHANGE_REPOSITORY` | `your-org/delta_exchange` | Second checkout; workflow links it to `../delta_exchange` for Bundler. |

If that variable is set but checkout or permissions fail, the link step errors with a targeted message.

### Path gem `ollama-client`

`backend/Gemfile` may reference `gem "ollama-client", path: "../../../ai-workspace/ollama-client"`. On CI or clones **without** that sibling directory, `bundle install` fails unless you vendor the gem, change the path, or use a published version. Local dev: clone or symlink **`ai-workspace/ollama-client`** next to the repo as implied by the path, or adjust the `Gemfile` for your layout.

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

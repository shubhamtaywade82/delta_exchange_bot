#!/usr/bin/env bash
# Optional second checkout: only required when backend/Gemfile pins delta_exchange via path: ../../delta_exchange.
# When DELTA_EXCHANGE_REPOSITORY is unset, Bundler uses the Gemfile source (e.g. rubygems.org) and no symlink is needed.
set -euo pipefail

if [ -z "${DELTA_EXCHANGE_REPOSITORY:-}" ]; then
  echo "Skipping delta_exchange path symlink (DELTA_EXCHANGE_REPOSITORY not set)."
  exit 0
fi

if [ -d "${GITHUB_WORKSPACE}/delta_exchange" ]; then
  ln -sfn "${GITHUB_WORKSPACE}/delta_exchange" "${GITHUB_WORKSPACE}/../delta_exchange"
fi

if [ ! -d "${GITHUB_WORKSPACE}/../delta_exchange" ]; then
  echo "::error::DELTA_EXCHANGE_REPOSITORY is set but ../../delta_exchange is missing after checkout. Fix the variable, PAT permissions, or repository name."
  exit 1
fi

echo "Linked ../../delta_exchange -> workspace delta_exchange checkout."

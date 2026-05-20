# SDK Repo Wrappers for Skill Drift Detector

These files are examples of how to install `sentry-skill-drift` workflows in each SDK repo.

Copy the matching file into your SDK repo at `.github/workflows/sentry-skill-drift.yml`.

## Onboarding in this org (`getsentry/sentry-for-ai`)

An org admin should:

1. Create the **Sentry Skill Drift** GitHub App.
2. Install it on `getsentry/sentry-for-ai` with write access and on each SDK repo with read access.
3. Store these organization-level secrets so SDK repos inherit them:
   - `SENTRY_AI_ANTHROPIC_API_KEY`
   - `SENTRY_SKILL_DRIFT_APP_ID`
   - `SENTRY_SKILL_DRIFT_APP_PRIVATE_KEY`

## Onboarding per SDK repo

1. Copy the correct wrapper workflow from this directory into
   `.github/workflows/sentry-skill-drift.yml`.
2. Adjust `branches:` if needed for that repo's default branch.
3. Commit and merge.

Once merged, each PR merge on main/master/develop in the target repo will call
`sentry-for-ai/.github/workflows/flue-skill-drift-detector-reusable.yml@main` with
just enough context to run a per-repo detector execution.

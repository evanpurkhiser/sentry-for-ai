# Flue Implementation Notes

This document captures cross-cutting implementation details for the Flue skill-drift automation system (Detector, Updater, Creator workflows).

---

## 1. Why Flue

The skill-drift automation is now designed as an inverted architecture: each SDK repo owns a per-PR detector trigger, while this repo only provides the shared Flue runtime pieces. The `sentry-for-ai` repo hosts the reusable detector workflow and reusable detector actuation logic; SDK repos send detector invocations for their own merged changes.

Updater and Creator are no longer CI-coupled CI workflows here. They are local-first CLI tools and exist to help operators and engineers with manual work when a detector action needs hands-on edits.

---

## 2. Architecture at a glance

```text
┌───────────────────────────────────────────────────────────────┐
│ Per-SDK-repo workflow (e.g. getsentry/sentry-android)         │
│ on: pull_request: types: [closed]                             │
│ if: pull_request.merged == true                               │
│ uses: getsentry/sentry-for-ai/.github/workflows/                │
│   flue-skill-drift-detector-reusable.yml@main                 │
└───────────────────┬───────────────────────────────────────────┘
                    │ workflow_call with skill_name, sdk_repo,
                    │ pr_number, pr_url
                    ▼
┌───────────────────────────────────────────────────────────────┐
│ Reusable workflow in getsentry/sentry-for-ai                  │
│ • detect job: checkout skills repo, run Flue agent,       │
│   output JSON actions array                                    │
│ • actuate job: apply patches, open PRs/issues in              │
│   getsentry/sentry-for-ai via GitHub App token                │
└───────────────────────────────────────────────────────────────┘
                    │ (skill-drift labeled PR opens)
                    ▼
┌───────────────────────────────────────────────────────────────┐
│ skill-drift-assign-reviewers.yml (unchanged)                  │
│ Routes the PR to the right SDK team based on changed paths    │
└───────────────────────────────────────────────────────────────┘

Separately (local-only, no CI trigger):
┌───────────────────────────────────────────────────────────────┐
│ Updater & Skill Creator                                        │
│ Invoked via ./scripts/test-flue-updater.sh and                │
│ ./scripts/test-flue-creator.sh                                │
│ Edits files locally; human reviews and opens PR manually       │
└───────────────────────────────────────────────────────────────┘
```

---

## 3. gh-aw \u2192 Flue mapping table

| gh-aw primitive | Flue equivalent |
| --- | --- |
| Trigger model | Push from each SDK repo (per-PR via wrapper workflow \u2192 reusable workflow) vs the gh-aw pull model (full scan across all repos) |
| Cron schedule | Per-PR `pull_request: types: [closed]` in each SDK repo's wrapper |
| engine: claude | unchanged |
| safe-outputs.create-pull-request | Agent edits files; actuator step commits and `gh pr create -R getsentry/sentry-for-ai` via App token |
| safe-outputs.create-issue | Agent writes issue payload; actuator opens issue in `getsentry/sentry-for-ai` |
| protected-files: fallback-to-issue | unchanged (`^skills/` allow-list still applies) |
| assignees: [copilot] (Updater trigger) | N/A — Updater is now invoked locally via `./scripts/test-flue-updater.sh` |
| github/* MCP toolset | unchanged |
| network.allowed: [mcp.sentry.dev] | unchanged (still dropped in this repo) |
| agentics-maintenance.yml | unchanged (still dropped) |
| add-reviewer safe output | unchanged (deterministic workflow handles it) |
| gh aw compile | unchanged (still N/A in Flue port) |
| concurrency: gh-aw-${{ github.workflow }} | `concurrency: flue-skill-drift-detector-${{ inputs.sdk_repo }}-${{ inputs.pr_number }}` |

---

## 4. File layout

```text
.flue/
  agents/
    skill-drift-detector.ts
    skill-drift-updater.ts
    skill-creator.ts
  roles/
    detector.md
    updater.md
    creator.md

.github/workflows/
  flue-skill-drift-detector-reusable.yml

docs/agent-port/
  01-skill-drift-detector.md
  02-skill-updater.md
  03-supporting-infrastructure.md
  04-flue-implementation.md
  sdk-repo-wrappers/
    README.md
    sentry-android.yml
    sentry-cocoa.yml
    sentry-dotnet.yml
    sentry-elixir.yml
    sentry-flutter.yml
    sentry-go.yml
    sentry-javascript-browser.yml
    sentry-javascript-cloudflare.yml
    sentry-javascript-nestjs.yml
    sentry-javascript-nextjs.yml
    sentry-javascript-node.yml
    sentry-javascript-react-router-framework.yml
    sentry-javascript-react.yml
    sentry-javascript-svelte.yml
    sentry-javascript-tanstack-start.yml
    sentry-php.yml
    sentry-python.yml
    sentry-react-native.yml
    sentry-ruby.yml

scripts/
  test-flue-detector.sh       # primary local invocation for Detector
  test-flue-updater.sh        # primary local invocation for Updater
  test-flue-creator.sh        # primary local invocation for Creator
  fixtures/
    flue-detector-*.json
    flue-updater-issue.json
```

Deleted workflow files from this repo:
- `flue-skill-drift-updater.yml`
- `flue-skill-creator.yml`
- `flue-skill-drift-detector.yml`

The Updater + Creator agents, roles, scripts, and role prompts are unchanged; only their workflow entries no longer exist as GitHub Actions entry points here.

---

## 5. Output schemas

Detector receives a 4-field input payload (`skill_name`, `sdk_repo`, `pr_number`, `pr_url`) and outputs single-skill actions. The per-action `skill` field is removed because each run is already scoped to one `skill_name` input from the wrapper.

Example shape still expected:

```json
{
  "actions": [
    {
      "type": "create_pr|create_issue|skip",
      "title": "[skill-drift] ...",
      "body": "...",
      "patch": "--- /dev/null\n+++ b/file.md\n@@ ..."
    }
  ],
  "summary": "..."
}
```

Updater and Creator schemas are unchanged from this PR's existing implementation.

---

## 6. Protected-files pattern

**The actuator uses an allow-list, not a deny-list.** The agents are designed to edit only files under `skills/`. Any path outside `skills/` triggers a downgrade-to-issue, which is the safer default for LLM-emitted patches.

```bash
ALLOWED_PATTERN='^skills/'
```

The check iterates over the agent's diff output and rejects any path that does not match:

```bash
ALLOWED_PATTERN='^skills/'
violation=""
while IFS= read -r path; do
  # Skip empty lines
  [[ -z "$path" ]] && continue
  # Strip ./ prefix defensively (git diff normalizes, but be explicit)
  normalized="${path#./}"
  if ! [[ "$normalized" =~ $ALLOWED_PATTERN ]]; then
    violation="$path"
    break
  fi
done <<<"$touched"

if [[ -n "$violation" ]]; then
  # downgrade-to-issue path
fi
```

### Why allow-list beats deny-list

Deny-lists require enumerating every sensitive path that might exist now or in the future. An LLM-influenced patch can touch a path that was never thought of — and it silently passes. Examples the old deny-list missed:

- `.husky/` — git hooks
- `.npmrc` — registry credentials
- `Dockerfile` — container build config
- `.env*` — environment variables
- `renovate.json` — dependency-update config
- `.changeset/` — release automation
- `.devcontainer/` — dev environment config
- Top-level `*.sh` scripts
- `commitlint.config.*`, `vitest.config.*`, `eslint.config.*`

An allow-list captures the invariant instead: **agents only edit skill files**. Everything else is naturally protected — current paths, future paths, and paths nobody thought to enumerate.

This addresses Warden security review **BRT-8PC** (PR #127).

> **Maintenance note:** The `ALLOWED_PATTERN` regex appears in two workflow files:
> - `.github/workflows/flue-skill-drift-detector-reusable.yml` (`detect` + `actuate` jobs)
> - `.github/workflows/agentics-maintenance.yml` (if added later)
>
> If you need to update the pattern (e.g. allow `docs/` for a new agent role), update it in every file where the actuator runs.

---

## 7. How to run locally

### Updater

Run locally to refresh existing skill content from a real issue or fixture:

```bash
./scripts/test-flue-updater.sh [--issue <N>|--fixture]
```

Updater is the PRIMARY invocation path for issue-driven updates in this repo. It edits the working tree and the operator is expected to review and submit the PR manually.

### Creator

Run locally to bootstrap a new platform skill:

```bash
./scripts/test-flue-creator.sh <platform> [prompt]
```

Creator is the PRIMARY invocation path for creating new skills in this repo. It writes directly to disk and requires manual review before submission.

### Detector

Primary invocation is via per-SDK-repo wrapper workflows on merged PRs. For debugging, use the smoke test:

```bash
./scripts/test-flue-detector.sh <skill_name> <sdk_repo> <pr_number>
# or
./scripts/test-flue-detector.sh --fixture
```

The smoke test is for local validation and does not replace CI wiring.

---

## 8. Cutover plan

1. Day 1: Updater and Creator gh-aw / Copilot infrastructure is obsolete. These agents remain available as local CLI tools.
2. Detector rollout is per-repo: start with a pilot SDK repo (recommended `sentry-go`, small and owned by `team-web-sdk-backend`), observe several merged PRs, then expand to the remaining 18 SDK repos.
3. Once 19 SDK repos are emitting reliable per-repo detector PRs/issues, remove the old gh-aw infrastructure:
   - `skill-drift-check.md`
   - `skill-drift-check.lock.yml`
   - `skill-updater.agent.md`
   - `skill-creator.agent.md`

---

## 9. Risks

- **Cross-repo write authentication** relies on a GitHub App with repository write scope for `getsentry/sentry-for-ai`.
- App private key must rotate regularly and stay in sync with org secret distribution.
- If the App is uninstalled or permissions are reduced, detector runs fail deterministically: `actions/create-github-app-token@v2` exits with a clear error and no silent fallback behavior.

---

## 10. Open questions / known gaps

- There is still no expiry/maintenance workflow for `skill-drift` PRs/issues; this is now naturally bounded by per-PR triggering and does not accumulate across all repos at interval cadence.
- No `mcp.sentry.dev` access at run-time in this architecture.
- Could add a pre-LLM bash path filter in the reusable workflow if action volume becomes a measurable cost issue. Per-PR gating already constrains volume via workflow `paths-ignore` in SDK wrappers.

---

## 11. Operational references

Keep `03-supporting-infrastructure.md` and `skill-drift-assign-reviewers.yml` as the source for stable reviewer-routing details and team ownership mapping.

---

## 12. Post-review fixes (PR #127)

### 12.1 Detector output schema

*(Documented in 01-skill-drift-detector.md)*

### 12.2 Updater patch application

*(Documented in 02-skill-updater.md)*

### 12.3 Skill tree validator step ordering

The Updater and Creator actuate jobs run the skill-tree validator **after** the protection check, not before. This is intentional:

1. Protection check runs against the agent's patch only
2. Validator runs on the post-check working tree
3. Validator's own regeneration of `SKILL_TREE.md` is committed in addition to the agent's patch

Moving the regen step before the protection check would be wrong: it would add `SKILL_TREE.md` to the diff before the check runs, causing every successful update to trip the violation guard.

### 12.4 Miscellaneous actuator hardening

Various small fixes to error handling, branch naming, and issue body formatting landed in `409e059`.

### 12.5 Allow-list hardening (Warden BRT-8PC)

Identified during PR #127 review by Warden bot (severity: HIGH). The original deny-list regex was structurally weak for LLM-emitted patches — any sensitive path not explicitly listed would pass through. Replaced with a `^skills/` allow-list across all workflows. See §6 for the full rationale and regex.

---

## 13. SDK repo onboarding

1. Org admin creates the GitHub App **"Sentry Skill Drift"** once:
   - `contents: write`, `pull-requests: write`, `issues: write` on `getsentry/sentry-for-ai`
   - `contents: read` on each SDK repo to be onboarded
2. Install the app on `getsentry/sentry-for-ai` and the target SDK repos.
3. Set org-level secrets so they are inherited by every SDK repo:
   - `SENTRY_AI_ANTHROPIC_API_KEY`
   - `SENTRY_SKILL_DRIFT_APP_ID`
   - `SENTRY_SKILL_DRIFT_APP_PRIVATE_KEY`
4. In the SDK repo, copy the matching wrapper from `docs/agent-port/sdk-repo-wrappers/<skill>.yml` to
   `.github/workflows/sentry-skill-drift.yml`.
5. Adjust `branches:` to the SDK repo default branch (`main`, `master`, or `develop` as appropriate).
6. Open and merge that PR; the next merged repo PR will trigger the detector with context for the corresponding skill.

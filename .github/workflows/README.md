# Workflows: names and conventions

GitHub only reads `*.yml` / `*.yaml` in this folder, so this file is documentation. `scripts/test-guards.sh` enforces the rules marked
(checked).

## Naming

| Kind | File | `name:` | Triggers |
|---|---|---|---|
| Entry workflow (starts on an event) | `tf-<what>.yml`, add `ai` when a model is involved: `tf-check.yml`, `tf-ai-analysis.yml` | the file name without `.yml` (checked) | any event except `workflow_call` |
| Reusable workflow (called by others) | `reusable-<what>.yml` (checked) | the file name without `.yml` (checked) | only `workflow_call` (checked) |

- `tf-` marks pipelines of this Terraform platform repository. A second domain gets its own prefix.
- `ai` in the name means a model runs (or can run) in it, so a reader can see where the model key is used.
- Reusable workflows describe what they do (`reusable-checkov`, `reusable-tf-ai-write`), not who calls them.
- The `name:` equals the file name, so a run in the Actions list maps to its file without guessing.

## Jobs, concurrency, artifacts

- Job ids are short lowercase words (`detect`, `verify`, `commit`); the job `name:` is what people read on the pull request.
  A job that calls a reusable workflow shows as `<job name> / <reusable job name>`.
- Concurrency groups start with the workflow name: `tf-check-<pr>`, `tf-ai-analysis-<pr>-<person|bot>`, `tf-ai-commands-<pr>-...`.
- Two callers of one reusable workflow in the same run need different artifact names (`reusable-checkov` takes `artifact_name`).
- Comment markers (`<!-- tf-test-agent-analysis -->`, `<!-- tf-test-agent-run ... -->`) are part of a stored contract with existing
  pull request comments; do not rename them with the workflows.

## Rules for secrets

- Reusable workflows get secrets one by one from the caller, never `secrets: inherit` (checked).
- A job holds at most one of: the model key, the App token. See the header of `tf-ai-commands.yml`.
- Every event a workflow uses must be allowed in the Actions event policy: `docs/actions-policy.md` (checked).

## Inventory

| File | Starts on | Calls | What it does |
|---|---|---|---|
| `tf-check.yml` | `pull_request` | `reusable-checkov` | lint, Checkov, `terraform test` of changed directories, one hint comment. No model, no secrets |
| `tf-ai-analysis.yml` | `pull_request_target` | `reusable-checkov`, `reusable-tf-ai-write` | the agent decides what the change needs (read-only), and writes tests when it decides they are needed |
| `tf-ai-commands.yml` | `issue_comment` | `reusable-tf-ai-write` | `agent coverage`, `agent check comments`, `agent remove <sha>` |
| `tf-cache-warm.yml` | `push` (main), `schedule`, `workflow_dispatch` | | provider and CodeGraph caches |
| `reusable-checkov.yml` | `workflow_call` | | one Checkov scan, SARIF artifact |
| `reusable-tf-ai-write.yml` | `workflow_call` | `reusable-checkov` | agent writes tests, verify without secrets, commit with the App token, report |

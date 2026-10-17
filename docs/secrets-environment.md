# Secrets live in an environment that only the default branch can use

The agent needs three secrets: `ANTHROPIC_API_KEY` (the model), `AGENT_APP_ID` and `AGENT_APP_PRIVATE_KEY` (the GitHub App that
pushes the agent's commits).

## The problem with repository secrets

A repository secret is readable by any workflow that runs in the repository, including a workflow *edited on a branch*. Anyone who
can push a branch can change a `pull_request` workflow to print the secrets and open a pull request. Everything else in this
design (the default-branch workflows, the job split, the path guards) assumes that the workflow file is trusted; a repository
secret does not enforce that.

## What this repository does instead

The three secrets are stored only as **environment secrets** of the environment `tf-ai-agent`, and that environment can be
used only by runs on the default branch. The workflows that run on the base branch (`pull_request_target`, `issue_comment`) are
allowed; a workflow on a pull request branch (`refs/pull/N/merge` or a feature branch) is refused before any step runs.

Tested on this repository with a throw-away workflow on a branch (a draft pull request, closed afterwards). Both triggers were
refused with the job showing zero steps:

- `pull_request`: `Branch "refs/pull/34/merge" is not allowed to deploy to tf-ai-agent due to environment protection rules.`
- `push` to the branch: `Branch "probe/env-secrets" is not allowed to deploy to tf-ai-agent due to environment protection rules.`

A job that does **not** declare the environment cannot read the secrets at all, as long as no repository-level copy exists.
That is why the repository-level secrets must be **deleted**, not just copied.

After the repository-level copies were deleted, a workflow on a branch that does not declare the environment printed
`key=0 app_id=0 app_key=0` (lengths of the three values). The comment commands and the automatic analysis ran successfully on
the environment secrets alone (`agent check comments` and a push by a person, both after the deletion).

In the workflows, only the jobs that use a secret declare `environment: tf-ai-agent`: `analyze` (tf-ai-analysis), `agent` and
`commit` (reusable-tf-ai-write), `creds` and `remove` (tf-ai-commands).

### Reusable workflows need the secrets declared and passed

A job inside a reusable workflow sees only the secrets that the workflow declares under `on.workflow_call.secrets` **and** that
the caller passes. A caller job cannot declare an environment, so it passes `${{ secrets.NAME }}` (a repository secret; empty once
the repository-level copies are deleted). The called job declares the environment, and the environment secret of the same name
takes precedence over the passed value. Tested on this repository with an environment-only secret:

| Called workflow | Caller | Value seen by the job |
|---|---|---|
| declares the secret | passes it by name | the environment value |
| declares nothing | `secrets: inherit` | the environment value |
| declares the secret | passes nothing | **empty** |

The first row is what `reusable-tf-ai-write` does (explicit; `secrets: inherit` is not used). The last row is the mistake that
broke the write path once: the secrets were set, and the jobs still saw nothing. `scripts/test-guards.sh` fails if a job reads
one of the secrets without declaring the environment, if a reusable workflow reads a secret it does not declare, or if
`secrets: inherit` appears.

## One-time setup

Replace `OWNER/REPO` and the branch name if the default branch is not `main`.

```sh
# 1. The environment, usable only from the default branch
gh api -X PUT repos/OWNER/REPO/environments/tf-ai-agent --input - <<'JSON'
{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
JSON
gh api -X POST repos/OWNER/REPO/environments/tf-ai-agent/deployment-branch-policies -f name=main -f type=branch

# 2. The secrets, as environment secrets
gh secret set ANTHROPIC_API_KEY --env tf-ai-agent
gh secret set AGENT_APP_ID --env tf-ai-agent
gh secret set AGENT_APP_PRIVATE_KEY --env tf-ai-agent < path/to/app-private-key.pem

# 3. Only after the workflows work with the environment: delete the repository-level copies
gh secret delete ANTHROPIC_API_KEY
gh secret delete AGENT_APP_ID
gh secret delete AGENT_APP_PRIVATE_KEY
```

The same can be done in the web interface: Settings, Environments, New environment `tf-ai-agent`, Deployment branches and tags,
Selected branches and tags, add `main`; then add the three secrets under Environment secrets.

Order matters, and it differs for the two kinds of job:

- A plain job that declares the environment also sees repository secrets, so it keeps working while the environment is still empty.
- A job inside a **reusable workflow** (`agent` and `commit` in `reusable-tf-ai-write`) reads the environment secret or gets what the
  caller passed. If the environment is empty and the repository-level copies are already deleted, it gets empty values: the agent
  step fails with "ANTHROPIC_API_KEY ... is required" and the commit step with "The 'client-id' (or deprecated 'app-id') input
  must be set".

So: create the environment and set its three secrets (steps 1 and 2), check that a run works (step 2 of "Check it"), and only
then delete the repository-level copies (step 3).

## Check it

1. `gh secret list` shows no repository-level secrets (the three names appear only with `gh secret list --env tf-ai-agent`).
2. A comment command and a pull request both work (`agent check comments`; the analysis comment appears). Each run lists a
   deployment to `tf-ai-agent` on the pull request.
3. Negative test: on a branch, a workflow that declares `environment: tf-ai-agent` is refused, and one that does not declare it
   sees empty secrets.

## Costs and limits

- Every job that uses the environment shows as a deployment on the pull request timeline, once per matrix leg.
- A repository admin can still change the environment's branch policy or replace the secrets. The control is aimed at people who
  can push branches, not at admins.
- Dependabot-triggered runs use Dependabot's own secrets, not these.
- If the default branch is renamed, the environment's branch policy must be changed too.

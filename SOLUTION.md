# Terraform test agent: solution notes

When a pull request changes Terraform, three things happen without anyone asking:

1. **Checks** (`tf-check`): lint, Checkov and the existing tests. No model, no secrets.
2. **Analysis** (`tf-ai-analysis`): for each changed directory the agent decides what is needed (tests needed, tests need an
   update, nothing to do, or not testable offline) and posts this decision, a test plan and findings. It is read-only.
3. **Writing**, on by default: when tests are needed, the agent writes them, a job without secrets runs them, and only tests
   that pass are **committed to the pull request branch**. You can switch this off with the label `no-auto-pr-agent` (one PR) or
   `AGENT_AUTO_WRITE=0` (whole repository).

People review the agent's commit like any other commit. They can also comment `agent check comments`, `agent coverage` or
`agent remove <sha>`. The agent only writes test files. People decide about the infrastructure code.

```text
pull_request ──► tf-check:  detect ─► lint, checkov ─► verify existing tests (no secrets) ─► hint comment

pull_request_target ──► tf-ai-analysis:
    detect ─► checkov ─► analyze (model key, read-only, no Terraform) ─► select (script) ─┬► post comment
                                                                                         └► reusable-tf-ai-write

comment ──► tf-ai-commands:  `agent coverage [dir]`, `agent check comments` ─► gate ─► reusable-tf-ai-write
                             `agent remove <sha>`                           ─► gate ─► git revert (App token, no model)

reusable-tf-ai-write:  round 1 ─► round 2 (failed directories only) ─► commit (App token) ─► report
reusable-tf-ai-round:  agent (model key, writes files, no Terraform) ─► verify (no secrets: fmt, validate, test, mutation)
```

## Where things are

| What | Where |
|---|---|
| **Custom agent** | `.claude/agents/tf-test-agent.md`: role, hard rules, modes (`analyze`, `coverage`, `revise`, `fix`) |
| **Skills** | `.claude/skills/`: `tf-change-analysis`, `tf-test-writing`, `tf-test-verify`, `tf-review-findings`, and HashiCorp's `terraform-test` (pinned, see `PROVENANCE.md`) |
| Workflows | `.github/workflows/` (rules in its `README.md`) |
| Scripts (no model) | `.github/scripts/`: directory detection, path guard, test-quality check, verify, mutation check, commit and revert, comment rendering. Tested by `scripts/test-guards.sh` (seconds, no Docker) |
| Prompts and tool lists | `.github/agent/`, shared by production and the evaluation suite |
| Evaluation suite | `evals/`, results in `docs/model-comparison.md` |
| More detail | `docs/decisions.md`, `docs/example-run.md`, `docs/setup.md`, `docs/security-review.md`, `docs/secrets-environment.md`, `docs/actions-policy.md`, `docs/lessons-from-github-runs.md` |

**How a run uses the skills:**

- `tf-change-analysis`: read the diff, find what depends on each changed symbol (CodeGraph, then `Grep` for tests), decide.
- `terraform-test` and `tf-test-writing`: syntax and house rules while writing. Where they disagree, the house rules win.
- `tf-test-verify`: run the static quality check. In the fix round, read the verification log.
- `tf-review-findings`: triage Checkov, add what a scanner cannot see, write the report JSON.

The analysis uses only the first and the last.

## Main decisions and their cost

The reasons and numbers behind each line are in `docs/decisions.md`.

| Decision | Why | What I gave up |
|---|---|---|
| Analyse every PR. Write tests automatically when needed | The task asks for it. A script, not the model, turns decisions into write jobs | The branch moves under the author. Authors must know the off switch |
| Loop breaker, a cap of 3 write runs per PR, two switches | Bot pushes never start the analysis. The cap limits cost | More than 3 runs need a person to comment `agent coverage` |
| Analysis on `pull_request_target`, read-only, no Terraform | The model key never meets a workflow the PR can edit. The PR is data, never run | The test plan is a proposal, not a result. Same-repository PRs only |
| The model never holds the write token and never runs Terraform | A prompt can be ignored, a job boundary cannot | The agent writes blind. It gets one fix round with the log |
| One fix round only | Most failures have a small cause. More rounds mostly waste money | A test that needs two fixes is not committed |
| Tests are committed to the PR branch | Normal diff review, inline comments, PR checks run on them | Needs a GitHub App: one more long-lived secret |
| Secrets live in a `tf-ai-agent` environment, default branch only | A workflow edited on a branch cannot read them (tested) | Admins can still change the policy |
| Guards outside the model: paths, no `apply`, an assert in every run, no collection-vs-literal `==`, no pinned insecure defaults | They do not depend on the model behaving | The insecure-value list is a deny-list and grows by hand |
| Model text in comments is made inert | A steered report must not post links, images, mentions or fake sections | No Markdown in findings. Misleading plain text still gets through |
| Offline tests: `mock_provider`, `command = plan` | No credentials, no cost, same result every time | Shows configuration, not real Azure behaviour |
| Mutation check | Shows which simple breakages no test notices | Crude. A list of hints, not a score |
| One Checkov scan, split into new and existing findings | Known misconfigurations, cheap. The agent triages only new ones | A second scan of the base. Moved code counts as new |
| CodeGraph, built fresh per job | Follows `variable → local → resource`. Helped on a large module (19/20 vs 13–15) | No gain on this repo's small modules. Does not index `*.tftest.hcl` |
| Evaluation suite with fixed checks | Model, prompt and fix-round choices backed by numbers | 8 cases written by the author: a small sample |
| Default model `claude-haiku-5-5` | About USD 0.01 per analysis. Change it with `CLAUDE_MODEL` | Fewer edge-case tests than a larger model |
| Actions pinned to SHAs, changed directories from `git diff` | Supply chain | Updates take a deliberate step |

## How to run it

One-time setup (full steps and every variable: `docs/setup.md`):

1. Create the environment `tf-ai-agent`, limited to the default branch, with the secrets `ANTHROPIC_API_KEY`, `AGENT_APP_ID`
   and `AGENT_APP_PRIVATE_KEY` (`docs/secrets-environment.md`).
2. Create a GitHub App with **Contents** and **Pull requests** read/write and install it on this repository only.
3. Merge to the default branch. The agent, skills and workflows are read from there.
4. Before 2 November 2026, create an Actions event policy that allows `pull_request_target` (`docs/actions-policy.md`).
5. Create the labels `no-auto-pr-agent` and `auto-pr-agent`.

Then open a pull request from a branch of this repository. Comments from someone with write access:

| Comment | Effect |
|---|---|
| `agent coverage` | write tests for the changed directories (not capped) |
| `agent coverage modules/<name>` | write tests for one directory, changed or not |
| `agent check comments` | act on review threads on test files, reply, resolve what was done |
| `agent remove <sha>` | revert one agent commit |

Locally: `scripts/test-guards.sh`.

## Example run

**Pull request 63**: https://github.com/andrey-parkhomets/tf-platform-base/pull/63 (kept open, not to be merged). Full
walkthrough: `docs/example-run.md`.

| Step | Result |
|---|---|
| Analysis (skills `tf-change-analysis`, `tf-review-findings`) | A decision, test plan and findings for 5 directories. An injected instruction in a code comment was reported as **high** and not obeyed |
| Automatic writing | 3 commits: `databricks-workspace` (**10 passed**), `function-app` (**10 passed**), `key-vault` (**4 passed**). The cap stopped the rest |
| `agent check comments` | 2 threads fixed and resolved. 3 declined and left open, including one review comment carrying an injection |
| `agent remove <sha>` | Reverted by the App, no model |
| `agent coverage` on other modules | `private-endpoint`, `log-analytics-workspace`, `network`, `key-vault`: all passed. The stack was `skipped` with a finding, so public access in `prod` is not blessed by a test |

Scratch PR 39 showed the fix round keeping a correct assertion and reporting the module, not turning the test green.

## What the tests can and cannot show

**Can show:** the module sets the right arguments, validations accept and reject the right values, `for_each` and conditions
expand as intended, inputs reach the right resources, and a later change does not silently remove them.

**Cannot show:** that Azure accepts the configuration, any value the provider computes, runtime or network behaviour, RBAC
working, real cross-module wiring, or that a security default is *right*. A test written from the code can copy a mistake in
the code, so the agent reports insecure behaviour as a finding instead of testing it as correct.

## Assumptions

- Terraform >= 1.9, `azurerm ~> 4.0`, a public GitHub repository, PRs from branches of the same repository.
- Reviewers read the comments and commits. Findings inform; they do not block.
- One module or stack per directory, no nested modules.
- The API key has a spend limit. The App is installed on this repository only.
- "In the context of the pull request" is read as: results are PR comments, and tests are commits on the PR branch. This is my
  choice, not something the task states. A suggest-only mode is not built. See `docs/decisions.md`.

## Limitations

Full list: `docs/decisions.md`.

- Automatic writing moves the author's branch unless someone switches it off.
- The agent cannot run its tests, so the first attempt fails more often. A test that needs two fixes is not committed.
- The analysis cannot see whether existing tests pass.
- PR Terraform runs in `verify`, which has no secrets. `data "external"` can still run code there.
- Fork PRs get no agent run.
- The agent can write weak or wrong tests, and can wrongly decide "no change needed". Guards and the mutation check catch some
  of this. A reviewer must catch the rest.
- Prompt-injection defence is evidence from a few planted examples, not proof.
- Stack tests are out of scope.
- The evidence is a limited number of runs with one model on one repository.

## With many more modules, teams or repositories

- One shared repository for the agent, skills and workflows, called as reusable workflows.
- Per-repository skill overlays on a shared base.
- Batch the matrix (256 legs max) and cap spend per run.
- Shared runners with a warm provider cache. The App installed per organisation.
- Metrics: commits kept vs reverted, mutants caught, threads resolved, false findings.

## For a production version

- A required check: tests or an explicit waiver for each changed module.
- A bigger evaluation suite, run as a gate on every model or prompt change.
- Short-lived credentials for the model API, an egress allow-list, Terraform for the agent in a sandbox without the key.
- Signed commits, branch protection that requires `verify`, Dependabot for action SHAs.
- A per-PR token budget. Checkov results in code scanning.
- Integration tests against real resources in a temporary subscription, after merge.

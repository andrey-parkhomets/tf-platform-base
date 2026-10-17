# Terraform test agent: solution notes

A pull request that changes Terraform gets, automatically:

1. **Deterministic checks**: lint, Checkov, and the existing tests of the changed directories (`tf-check`). No model, no secrets.
2. **An agent analysis** (`tf-ai-analysis`) that decides, per changed directory, what the change needs: tests needed, tests need an
   update, nothing to do, or not testable offline. It posts the decision, the tests it would write and the findings reviewers should
   see. The analysis is read-only: no Terraform, no write token, nothing pushed.
3. **Writing tests**, which is **opt-in**: when the decision is "tests needed" or "tests need an update" and the pull request has the
   label `auto-pr-agent` (or the repository sets `AGENT_AUTO_WRITE=1`), the agent writes `terraform test` files, a job without
   secrets runs them, and only the verified tests are **committed to the pull request branch**. Without the opt-in the analysis only
   recommends, and says how to ask (`agent coverage`, or the label). The branch moves under the author when the agent commits, so a
   person has to choose that.

People review that commit like any other, leave inline comments and ask the agent to act on them (`agent check comments`), ask for
tests by hand (`agent coverage`), or revert a commit (`agent remove <sha>`). Decisions about the infrastructure code itself stay
with people: the agent writes only test files and tells reviewers what it noticed.

```text
pull_request ──► tf-check:  detect ─► lint, checkov (reusable) ─► verify (existing tests, no secrets) ─► hint comment

pull_request_target ──► tf-ai-analysis:
    detect (no secrets) ─► checkov (reusable) ─► analyze (model key, read-only, no Terraform) ─► select (script) ─┬► post (comment)
                                                                                                                 └► write = reusable-tf-ai-write

comment ──► tf-ai-commands:   `agent coverage [dir]`  `agent check comments`  ─► gate ─► write = reusable-tf-ai-write
                              `agent remove <sha>`                             ─► gate ─► git revert (App token, no model)

reusable-tf-ai-write:  checkov (skipped if the caller scanned) ─► round 1 ─► round 2 (only for failed directories) ─► commit (App token) ─► report
reusable-tf-ai-round:  agent (model key, writes files, NO Terraform) ─► verify (no secrets: fmt, validate, test, mutation) ─► summary
```

## Where things are

| What | Where |
|---|---|
| **Custom agent** | `.claude/agents/tf-test-agent.md`: role, hard rules, three modes (`analyze`, `coverage`, `revise`), tool list |
| **Skills** | `.claude/skills/`: `tf-change-analysis`, `tf-test-writing`, `tf-test-verify`, `tf-review-findings`, and the vendored HashiCorp `terraform-test` (pinned, see its `PROVENANCE.md`) |
| Workflows | `.github/workflows/`: entry workflows `tf-check`, `tf-ai-analysis`, `tf-ai-commands`, `tf-cache-warm`; reusable `reusable-checkov`, `reusable-tf-ai-write`, `reusable-tf-ai-round`. Names and rules: `.github/workflows/README.md` |
| Deterministic scripts | `.github/scripts/` (command grammar, directory detection, path guard, test-quality check, verification, mutation check, commit and revert, review threads, comment rendering, automatic-write selection, making model text inert, scoping Checkov results). Tested by `scripts/test-guards.sh` (seconds, no Docker) |
| More detail | `docs/secrets-environment.md` (where the secrets live), `docs/actions-policy.md` (Actions event policy to create), `docs/security-review.md`, `docs/model-comparison.md`, `docs/lessons-from-github-runs.md` |

**How a run uses the skills.** `tf-change-analysis`: read the diff with a fixed command, ask CodeGraph who depends on the changed
symbols, read the static test-quality result, decide per directory (`tests_needed`, `tests_need_update`, `no_change_needed`,
`skipped`; when writing: `created`, `updated`). `terraform-test` (syntax, from HashiCorp) and `tf-test-writing` (house rules; this
repo's skill wins where they disagree) while writing. `tf-test-verify`: run only the static quality check, and in the fix round read the verification log. `tf-review-findings`:
triage Checkov, add what a scanner cannot see, write the report JSON, including one outcome per review thread. The analysis mode uses
`tf-change-analysis` and `tf-review-findings` only.

## Main decisions, and what each one costs

| Decision | Why | What I gave up |
|---|---|---|
| **The agent decides on every PR, recommends, and writes only when asked or opted in; everything it commits can be undone** | The task asks for an agent that creates or updates tests when it judges that appropriate, and results must be in the PR. The decision is a cheap read-only run per directory. Committing moves the author's branch (they must pull before the next push), so it is opt-in: the label `auto-pr-agent` on the PR (only counts when applied by someone with write access), the repository variable `AGENT_AUTO_WRITE=1`, or a comment `agent coverage`. Writing is one pipeline (`reusable-tf-ai-write`) for all three. A tested script, `select-auto-write.sh`, not the model, turns decisions into directories and applies the opt-in, the opt-out and the cap | Tests do not appear on their own unless someone opts in: the recommendation can sit unread. A wrong "tests needed" costs one model run, and a commit that `agent remove <sha>` undoes |
| **Loop breaker, cap and opt-in/out** | Pushes by bots (the agent's own commits) never start the analysis, so there is no loop; a push by a person starts it again, so on an opted-in PR each human push can trigger one automatic write. Adding the label `auto-pr-agent` starts it at once. At most `AGENT_AUTO_WRITE_MAX` (3) agent commits per PR. The label `no-auto-pr-agent` turns automatic writing off even when the repository opted in; `AGENT_AUTO_ANALYSIS=0` turns the analysis off | A fourth round needs a person to comment `agent coverage` |
| **The analysis runs on `pull_request_target`, read-only, without Terraform** | The model key must not be exposed to a workflow the PR can edit, so the workflow, agent and skills come from the default branch. The PR is checked out as data and never executed: Terraform is not installed in the job, tools are `Read/Grep/Glob/Skill`, `git diff/log/status`, `codegraph explore` and the report file, and a guard fails the job if any file changed. The comment is posted by a separate job that has the write token and no model | The analysis cannot see test results, so its test plan is a proposal, not a claim. Same-repository PRs only, no drafts, no bot pushes, at most 5 directories per run. Needs an Actions event policy after 2 November 2026 (`docs/actions-policy.md`) |
| **Verified tests are committed to the PR branch** | Reviewable in the normal diff with inline comments, and the PR's own checks run on them | Needs a GitHub App (a `GITHUB_TOKEN` push would not start the checks): one more long-lived secret |
| **The model never holds the write token and never runs Terraform**: `agent` (model key, no Terraform), `verify` (nothing), `commit` (App token) | A prompt can be ignored, a job boundary cannot. Terraform is not installed in the agent job and no Terraform command is allowed, so PR code (`data "external"` runs at plan time) never executes next to the key; it executes only in `verify`, which has no secrets. The pushed bytes are exactly the patch `verify` accepted, and `commit-patch.sh` re-checks the paths | The agent writes blind and cannot check its own work. Mitigations: it runs the static quality check; `verify` formats the files itself; one bounded fix round gives it the failing log. More latency and spend when round 1 fails |
| **One fix round, no more** | A failing verification usually has a small, local cause (a wrong attribute, a mock quirk). The agent gets the log of the failed round once; a third round would mostly burn money on a test that cannot be fixed. Round 2 runs only for the directories that failed | A test that needs more than one correction is not committed; the comment shows what failed |
| **Secrets are environment secrets of `tf-ai-agent`, usable only from the default branch** | A repository secret is readable by any workflow in the repository, including one edited on a branch, so branch writers could print it. Tested: a `pull_request` workflow and a `push` workflow on a branch that declare the environment are refused before any step runs | Jobs that use a secret declare the environment and show as deployments on the PR. Someone with admin rights can still change the policy |
| **Guards outside the model** | Only `(modules\|stacks)/*/tests/*.tftest.hcl` and `.tfmock.hcl` may change; no `command = apply`, no run without an assert, no constant condition. These are structural and complete. A further check rejects an assert that pins an insecure default (public network access, weak TLS, shared keys): it is a **backstop** for the prompt rule "do not bless insecure behaviour", which the model once broke, not the control that makes a test right. It is a deny-list, so it catches only the settings on its list. What stops a wrong test is the reviewer, helped by the findings | A legitimate fixture file in `tests/` needs the path guard extended; the insecure-value list grows by hand and will always lag |
| **Everything the model writes into a PR comment is made inert** | A report may have been steered by an injected diff or review comment, and it ends up in a comment from the bot's account, which readers trust. A probe against the first version showed a rendered image beacon, a phishing link, autolinkable URLs and a *forged* "Committed to this branch" line in the comment. Now only known keys of the report survive, each value is one line with links, images, HTML, mentions, `#123` references, fences, zero-width and bidirectional characters, and control characters defused (`inert.jq`), enumerations and identifiers (paths, skill and run names, thread ids) are validated, and lists and lengths are bounded. The same filter covers commit-message text, review replies and error messages. Tested adversarially: hostile reports go through both renderers and nothing may render as a link or forged section; each defence has a test that fails when it is removed | The agent cannot use links or Markdown formatting in its findings (paths and code names still show as text). A filter works on syntax: the model can still write *misleading plain text*, so the findings stay information for a reviewer, not a verdict |
| **Review loop by comment** (`agent check comments`) | Inline comments on the agent's test lines are the natural way to ask for a change. The agent replies and resolves the threads it addressed, and leaves the others open for a person | Only threads on `tests/` files from people with write access are read |
| **`agent remove <sha>` is a `git revert`** | Non-destructive: no rewritten history, no force-push, reviewers' links keep working. Only commits authored by the App, inside the PR, touching only test files | The commit stays in history next to its revert |
| **Comment commands: `issue_comment`, default-branch workflow, write permission, one-line grammar** | A PR cannot rewrite the workflow, the agent file or the skills. Commands match a strict regex; chatter and quoted commands do nothing | Fork PRs get no agent. A change to the workflow, agent or skills applies after merge, and the PR that introduces it cannot run it |
| **Offline tests: `mock_provider` and `command = plan`** | No credentials, no cost, deterministic | Tests show configuration and wiring, not provider behaviour (see below) |
| **Mutation check as a gap detector** | It breaks the module in simple ways in a temporary copy (flip a boolean, change a string, drop `tags`) and lists breakages no test noticed. A survivor means "no test checks this", nothing more | Four crude operators, first match only; some survivors are harmless. A list of hints, not a score |
| **One Checkov scan, reusable, scoped afterwards** (`reusable-checkov`, `scope-sarif.sh`) | Cheap and certain for known misconfigurations. The workflow scans the whole repository (some checks are graph checks that need the stack around a module) and the base commit as well, in a parallel job. `scope-sarif.sh` then keeps the findings below the changed directory and marks each `new` (not on the base) or `existing`. The agent triages the new ones; the comment says "N findings in the changed directories, X new and Y already on the base; whole repository: K". `soft_fail`, informational | A second scan per run (parallel, no extra wait). A moved or renamed resource shows its findings as new again; the baseline is scanned with the base commit's own Checkov configuration |
| **CodeGraph index, cached from `main`** | The agent finds callers and dependants (Terraform resources, variables, modules). Pinned version, `--ignore-scripts`; PRs only restore the cache and sync | A third-party tool in the agent job. Cache hit rate depends on eviction (`tf-cache-warm`) |
| **Changed directories from `git diff`, no third-party action** | `detect-modules.sh` derives the matrix from `BASE...HEAD` and validates every name (`^(modules\|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$`, no `..`) before use; changed-files actions have been compromised in the supply chain | Nothing |
| **Actions pinned to commit SHAs, `ubuntu-24.04`** | Supply chain and a stable runner image | Updates are deliberate |
| **Default model `claude-haiku-5-5`** | Low cost per run (an analysis is about USD 0.01; `CLAUDE_MODEL` changes the model) | Fewer edge-case tests than a larger model; see `docs/model-comparison.md` |

## How to run it

One-time setup:

1. An environment `tf-ai-agent` that only the default branch can use, holding three **environment secrets**: `ANTHROPIC_API_KEY`
   (read only by the jobs that run the model), and `AGENT_APP_ID` and `AGENT_APP_PRIVATE_KEY` of a GitHub App (read only by the jobs
   that push). Delete any repository-level copies: a repository secret can be read by a workflow edited on a branch, an environment
   secret cannot. Set the environment secrets before the first run (jobs in reusable workflows read nothing else); commands, order and the check: `docs/secrets-environment.md`.
2. The GitHub App for the commits (Settings, Developer settings, GitHub Apps, New): repository permissions **Contents: Read and
   write**, **Pull requests: Read and write**, no webhook. Install it on this repository only. Without its secrets the comment
   commands say so and stop before spending anything.
3. Merge to the default branch. `issue_comment` and `pull_request_target` workflows and `.claude/` are read from there. Optionally
   run `tf-cache-warm` once.
4. **Before 2 November 2026:** create an Actions event policy that allows the events the workflows use, `pull_request_target`
   included. From that date GitHub blocks `pull_request_target` in public repositories without one, which would stop the automatic
   analysis. Exact settings and how to check them in Evaluate mode: `docs/actions-policy.md`.
5. Optional repository variables: `CLAUDE_MODEL`, `AGENT_MAX_TURNS` (60), `ANALYSIS_MAX_TURNS` (30), `ANALYSIS_MAX_DIRS` (5),
   `AGENT_AUTO_ANALYSIS` (`0` switches the analysis off), `AGENT_AUTO_WRITE` (`1` = automatic writing for every PR; default off, so the
   label is the opt-in), `AGENT_AUTO_WRITE_MAX` (3), `AGENT_SUBPROCESS_SCRUB` (`0` only to run without the subprocess scrub). Create the
   labels `auto-pr-agent` (opt in a PR) and `no-auto-pr-agent` (opt a PR out when the repository variable is on).

Using it, in a pull request from a branch of this repository: the checks and the analysis comment appear by themselves; the agent
commits tests when it decided they are needed and the PR carries the label `auto-pr-agent`. Comment commands (the whole comment, one line, from someone with write access):

| Comment | Effect |
|---|---|
| `agent coverage` | tests for the directories changed in the PR (not limited by the cap) |
| `agent coverage modules/<name>` | tests for one directory, changed or not |
| `agent check comments` | read unresolved review threads on test files, change the tests or decline with a reason, reply, resolve what was addressed |
| `agent remove <sha>` | revert one commit made by the agent |

Locally: `scripts/test-guards.sh` tests the deterministic scripts (command grammar, path guard, commit and revert rules, review
threads with a stubbed `gh`, test-quality checks, automatic-write selection, comment rendering, workflow naming rules).

## Example run

**Pull request 31:** https://github.com/andrey-parkhomets/tf-platform-base/pull/31 (a demonstration PR, kept open, not to be merged;
its comments hold the walkthrough). Model `claude-haiku-5-5`, real `claude-code-action`, GitHub App `andrey-tf-test-agent`. It changes
three modules: input validations in `databricks-workspace` (no tests; a deliberate prompt-injection canary sits in a comment of the
same file), `private-endpoint` (no tests) and `key-vault` (has tests, nothing covers the new rule).

| Step | What happened |
|---|---|
| PR opened | `tf-check` passed (lint, `Checkov / Scan`, verify of the existing tests, hint comment). `tf-ai-analysis` posted one comment with a decision per directory: all three `tests_needed`, each with a test plan. Skills used: `tf-change-analysis`, `tf-review-findings` |
| Findings in that comment | **high**: the comment in `variables.tf` that addresses AI reviewers was reported, not obeyed. No workflow file was edited (the branch diff touches only `variables.tf` and `tests/`), and the canary token appears in no report. **medium**: the all-zero placeholder tenant GUID in `prod.tfvars`, which the new validation accepts; Checkov's DBFS key finding. The agent called Checkov's key-vault private-endpoint finding a probable false positive at module scope, because the stack creates the endpoint |
| Automatic writing (at the time of this run automatic writing was on by default; it now needs the label `auto-pr-agent`) | Three commits by the App: `created` for `databricks-workspace` (**13 passed, 0 failed**, mutation check 2 of 2 caught), `updated` for `key-vault` (**3 passed**, 2 of 3 caught), `created` for `private-endpoint` (**10 passed**, 4 of 4 caught). Each verified in a job without secrets before the push. The bot pushes did not start another analysis; the analysis comment was marked "possibly out of date" |
| Two inline review comments on the key-vault test, then `agent check comments` | (1) "accept the all-zero placeholder GUID": the agent added a run, verification passed, the thread was answered and **resolved**. (2) "make this an apply-mode test against a real tenant": **declined** with a reason (offline plan-mode only), thread left **open** for a person |
| `agent remove e4e07bd` | Revert commit by the App, no model involved |
| A push by a person | The analysis ran again: the two directories with tests came back `no_change_needed`; `private-endpoint` came back `tests_needed` but was **not** written automatically, because the PR already had 4 agent commits (limit 3). The comment said so and named the command |
| `agent coverage modules/private-endpoint` | The manual command is not capped: tests written again, **10 passed**, 3 of 4 mutants caught |

**The agent without Terraform, scratch pull request 39** (closed; the reports of both runs are in its comments). Run through a throw-away
caller, with that one branch allowed in the environment for the duration; the caller and its runs were deleted afterwards. First run:
the existing test file had a run that referenced a resource that does not exist. The agent, with no Terraform available, corrected
that run and added seven more; `verify` formatted the files and ran them: **8 passed, 0 failed**, mutation check 3 of 4, committed;
the broken run was reported as a finding. Second run, with a second test file holding a plausible but false assertion
(`is_manual_connection == true`, the module sets `false`): round 1 failed verification (9 passed, 1 failed), round 2 read the log,
kept the assertion, reported a medium finding that the test and the module disagree, and nothing was committed. That is the intended
outcome of "do not turn an assertion around to make it green".

**Quality override, pull request 17** (`databricks-workspace`): the agent once pinned an insecure default in a test
(`public_network_access_enabled == true` on its default) and raised no finding. `check-test-quality.sh` fails such a run: the verify
job went red with "asserts public_network_access_enabled == true on its default", the analysis answered `tests_need_update`, and
`agent coverage` removed the run and reported the default as a finding (**12 passed, 0 failed**).

Other example pull requests that stay open: 7 (`log-analytics-workspace`, the review loop in the comment-only form) and 22
(`private-endpoint`, the automatic path; its analysis questions whether the regex should allow underscores).

## What the generated tests can and cannot show

They show: the module sets the arguments it is supposed to set (TLS, public access, identities, names), variable validations accept
and reject the right values, `for_each` and conditional resources expand as intended, inputs reach the right resources, and a later
change does not silently remove those properties.

They do not show: that Azure accepts the configuration (SKU, region, name rules, quotas, policy), anything the provider computes
(ids, IP addresses and principal ids are generated by the mock), runtime or network behaviour, RBAC actually working, cross-module
wiring in a real environment, or that a security default is **right**. A test written from the code can encode a mistake in the code,
so the agent must not bless insecure behaviour (for example `ftps_state = "AllAllowed"`) and raises it as a finding instead.

## Assumptions

- Terraform >= 1.9, `azurerm ~> 4.0`, a public GitHub repository, pull requests from branches of the same repository.
- Reviewers read the comments and the commits. Findings are information, not a gate.
- One module or stack per directory under `modules/` and `stacks/`; no nested modules.
- The `ANTHROPIC_API_KEY` belongs to a workspace with a spend limit. The GitHub App is installed on this repository only.
- Stacks are treated like modules by the tooling, but their tests are out of scope: without integration tests they add little
  beyond the module tests.

## Limitations

- Because writing is opt-in, a recommendation that nobody acts on stays a recommendation; nothing enforces it. Making "tests, or an
  explicit waiver" a required check is on the production list.
- The label `auto-pr-agent` can be applied by anyone with triage rights, which is less than write access. The workflow checks the
  permission of whoever applied it; a label already on the PR when a writer pushes counts, because that push is the writer's choice.
- The agent writes without being able to run its tests, so a first attempt fails more often than it would with a feedback loop; one fix
  round recovers most of it and costs time and tokens. A test that needs two corrections is not committed.
- The analysis cannot run Terraform, so it cannot tell whether the existing tests pass. It runs the static test-quality check
  before the model and enforces its result, but a test that is wrong in other ways is only found by the verify job.
- Terraform on pull request code runs only in the `verify` job, which has no secrets and a read-only token. `data "external"` can
  run a script at plan time there; with nothing to steal, the exposure is runner time and the read-only token. The model key and the
  App token are never in a job that executes the pull request's Terraform. They are environment secrets, not reachable from a
  workflow edited on a branch (`docs/secrets-environment.md`).
- Fork pull requests get no agent run, by design. A branch that moves during a run (the push fails, nothing is forced) has not been
  exercised on GitHub.
- The agent can still write weak or wrong tests. The guards catch structure and known insecure assertions, the mutation check
  catches some weakness, a reviewer catches the rest. A model that decides "no change needed" wrongly is only noticed by a person.
- A prompt-injection attempt in the diff or in a review comment is handled by the rules in the agent file, the tool allow-list, the
  job split and the path guard. One planted example was ignored; that is evidence, not a proof.
- The comment filter is syntactic. It stops injected links, images, HTML, mentions and forged sections; it cannot stop a model that
  has been talked into writing something false in plain words. The diff, not the comment, is what a reviewer approves.
- Findings are told apart from the base by rule, file and the first line of the resource, because the SARIF has no fingerprints and line
  numbers move; code that is moved or renamed counts as new. `tf-check` still shows the raw whole-repository result, and no SARIF is
  uploaded to code scanning.
- The evidence so far is a limited number of runs with one model on one public repository.

## Many more modules, teams or repositories

- One shared repository for the agent, skills and workflows, called as reusable workflows (they already are), so a change to a skill
  is one PR.
- Matrix limit is 256 legs: batch by team or directory count and cap spend per run (the analysis already caps directories).
- Per-repository `.claude/skills/` overlays on a shared baseline.
- Shared runner pool with warm provider and CodeGraph caches; the App installed per organisation with a token per repository.
- Metrics: how often the agent writes, commits kept versus reverted, mutants caught, threads resolved, false findings.

## For a production version

- Enforce the outcome: require tests (or an explicit waiver) for changed modules as a required check.
- An evaluation suite: a fixed set of changes with expected tests and findings, scored on every model or prompt change.
- Federated short-lived credentials for the model API, an egress allow-list on the runner, and Terraform for the agent in a
  container without the key.
- Signed commits through the API and branch protection that requires `verify`; Dependabot for action SHAs; a scheduled `tf-cache-warm`.
- Per-PR token budget. Checkov SARIF to code scanning (the scoped, new findings only).
- Integration tests (`terraform test` with real resources) in an ephemeral subscription on merge, outside this offline workflow.

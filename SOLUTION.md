# Terraform test agent: solution notes

A pull request that changes Terraform gets, automatically: deterministic checks (lint, Checkov, the existing tests of the
changed directories) and **an agent analysis that decides what the change needs** (tests needed, tests need an update, nothing
to do, not testable offline), lists the tests it would write and the findings reviewers should see. The analysis is read-only:
no Terraform, no write token, nothing pushed. **When the analysis decides tests are needed or need an update, the agent writes
them automatically** (same pipeline as `agent coverage`, see the limits below); a person can also ask by comment at any time.
The agent writes or revises `terraform test` files, a job with no secrets re-runs them, and the verified
tests are **committed to the pull request branch**. People review that commit like any other, leave inline comments, and ask
the agent to act on them or to revert the commit.

```text
pull_request_target ──► agent-analysis.yml:  detect (no secrets) ─► analyze (model key, read-only, no Terraform) ─► select (script) ─┬► post (comment)
                         "modules/x: tests_needed. Writing tests now. Findings: ..."                                   └► write = agent-write.yml
                                                                                                                          (agent ─► verify, no secrets ─► commit, App token)

pull_request ──► terraform-checks.yml:  detect ─► lint, checkov ─► verify (existing tests) ─► one hint comment
                                         "changed: modules/x (no tests). Comment `agent coverage`"

comment ──► agent-commands.yml
  `agent coverage [dir]`    gate ─► checkov ─► agent (model key) ─► verify (no secrets) ─► commit (App token) ─► report
  `agent check comments`    gate collects unresolved review threads on test files ─► same chain, then replies + resolves threads
  `agent remove <sha>`      gate ─► remove (App token): git revert of an agent commit, new commit, no model
```

## Where things are

| What | Where |
|---|---|
| Workflows | `.github/workflows/terraform-checks.yml` (every PR, no secrets, no model), `agent-analysis.yml` (every same-repo PR, model, read-only), `agent-commands.yml` (comment commands: gate, revert, and a call to) `agent-write.yml` (reusable: agent, verify, commit, report), `cache-warm.yml` (caches, `main` only) |
| **Custom agent** | `.claude/agents/tf-test-agent.md`: role, hard rules, three modes (`analyze`, `coverage`, `revise`), tool list |
| **Skills** | `.claude/skills/`: `tf-change-analysis`, `tf-test-writing`, `tf-test-verify`, `tf-review-findings`, and the vendored HashiCorp `terraform-test` (pinned, see `PROVENANCE.md`) |
| Deterministic scripts (tested by `scripts/test-guards.sh`) | `.github/scripts/`: `parse-command.sh`, `detect-modules.sh`, `guard-paths.sh`, `check-test-quality.sh`, `verify-module.sh`, `mutation-check.sh`, `commit-patch.sh`, `revert-commit.sh`, `collect-threads.sh`, `resolve-threads.sh`, `render-hint.sh`, `render-report.sh`, `render-analysis.sh` |
| Local checks | `scripts/test-guards.sh` (seconds, no Docker), pre-commit config, `.tflint.hcl`, `.checkov.yaml` |
| More detail | `docs/security-review.md`, `docs/model-comparison.md`, `docs/lessons-from-github-runs.md` |

How a run uses the skills: `tf-change-analysis` (read the diff, ask CodeGraph who depends on the changed symbols, decide
`created` / `updated` / `no_change_needed` / `skipped`; in `revise` mode, decide per review thread), then `terraform-test` plus
`tf-test-writing` (syntax from HashiCorp, house rules from this repo; the repo skill wins where they disagree), then
`tf-test-verify` (run the commands, read failures), then `tf-review-findings` (triage Checkov, add what a scanner cannot see,
write the report JSON, including the outcome per review thread).

## Main decisions, and what each one costs

| Decision | Why | What I gave up |
|---|---|---|
| **The agent decides on every PR and writes when it decides tests are needed; people can always ask or undo** | The task asks for an agent that creates or updates tests when it judges that appropriate. The decision is a read-only run per changed directory; writing reuses the audited comment-command pipeline (`agent-write.yml`, one implementation). `select-auto-write.sh` (a tested script, not the model) turns decisions into directories, applies the opt-outs and the cap | The branch moves under the author: they must pull before the next push. Opt out with the `no-auto-pr-agent` label or `AGENT_AUTO_WRITE=0`. A wrong `tests_needed` costs one more model run and one commit that `agent remove <sha>` undoes |
| **Loop breaker and cap** | Pushes by bots (the agent's own commits) never start the workflow; a push by a person does, so each human push can trigger one automatic write (that is the re-arm). At most `AGENT_AUTO_WRITE_MAX` (3) agent commits per PR, counted from the PR's own commits | A fourth round needs a person to comment `agent coverage` |
| **The automatic run is `pull_request_target`, read-only and without Terraform** | The model key must not be exposed to a workflow the PR can edit, so the workflow, agent and skills come from the default branch. The PR is checked out as data and never executed: no Terraform is installed, tools are `Read/Grep/Glob/Skill`, `git diff/log/status`, `codegraph explore`, and a report file. A guard fails the job if any file changed; the comment is posted by a separate job that has the write token but no model | The analysis cannot run tests or see test results, so its test plan is a proposal, not a claim. Same-repo PRs only, not drafts, not pushes by bots (the agent's own test commit would otherwise re-run it; the comment is then marked possibly out of date), at most 5 directories per run (`ANALYSIS_MAX_DIRS`). Kill switch: `AGENT_AUTO_ANALYSIS=0` |
| **Verified tests are committed to the branch** | Reviewable in the normal diff, with inline comments, and the PR's own checks run on them | Needs a GitHub App (a `GITHUB_TOKEN` push would not start the checks). One more long-lived secret |
| **Review loop by comment: `agent check comments`** | Inline comments on the agent's test lines are the natural way to ask for a change; the agent replies and resolves the threads it addressed, and leaves the others open for a person | Only threads on `tests/` files from people with write access are read. Threads on infrastructure code are out of scope |
| **`agent remove <sha>` is a `git revert`** | Non-destructive: history is not rewritten, no force-push, reviewers' links keep working. Only commits authored by the App, inside the PR, touching only test files | The commit stays in history next to its revert |
| **The model never holds the write token.** Three jobs: `agent` (model key), `verify` (nothing), `commit` (App token) | A prompt can be ignored, a job boundary cannot. The pushed bytes are exactly the patch `verify` accepted, and `commit-patch.sh` re-checks the paths | Two extra jobs per run. The agent job still runs `terraform test` on PR code next to the key (see Limitations) |
| **Path guard and static quality checks outside the LLM** | Only `(modules\|stacks)/*/tests/*.tftest.hcl` / `.tfmock.hcl` may change; no `command = apply`, no run without asserts, no constant conditions, no assert that pins an insecure default (public network access, weak TLS, shared keys...). The last one backs up the prompt rule "do not bless insecure behaviour", which the model broke once | A legitimate fixture file in `tests/` needs the guard extended |
| **`issue_comment`, default-branch workflow, same-repository PRs, write permission, one-line grammar** | The workflow, the agent file and the skills come from the default branch, so a PR cannot rewrite them. Commands are matched against a strict regex; chatter and quoted commands do nothing | Fork PRs get no agent. Changes to the workflow, agent or skills apply after merge, and the PR that introduces them cannot run them |
| **Offline tests: `mock_provider` + `command = plan`** | No credentials, no cost, deterministic | Tests show configuration and wiring, not provider behaviour (see below) |
| **Mutation check, as a gap detector** | It breaks the module in simple ways in a temporary copy (flip a boolean, change a string, drop `tags`) and lists the breakages no test noticed. It found a real gap (unasserted DNS zone group name). A surviving mutant means "no test checks this", nothing more | Four crude operators, first match only; some survivors are harmless. Treat the list as hints, not a score |
| **Checkov as a pre-filter** | Cheap and certain for known misconfigurations. The agent triages it in context and looks for what scanners miss. `soft_fail`, informational | Scans the whole repo, so old findings appear in the count |
| **CodeGraph index, cached from `main`** | The agent finds callers and dependants (it supports Terraform: resources, variables, modules, `var.`/`module.` references). Pinned version, `--ignore-scripts`; PRs only restore the cache and sync | A third-party tool in the agent job. Cache hit rate depends on eviction (`cache-warm.yml` should be scheduled) |
| **Changed directories from `git diff`, no third-party action** | The matrix is derived by `detect-modules.sh` from `BASE...HEAD`, and every name is validated (`^(modules\|stacks)/[A-Za-z0-9][A-Za-z0-9._-]*$`, no `..`) before use | Nothing; this replaced `tj-actions/changed-files` (compromised in 2025) |
| **All actions pinned to commit SHAs, `ubuntu-24.04`** | Supply chain and a stable runner image | Updates are deliberate (Dependabot is on the production list) |
| **Default model `claude-haiku-5-5`** | Keeps the cost of CI development low (about USD 0.02 per run); `CLAUDE_MODEL` changes it | Fewer edge-case tests than a larger model; see `docs/model-comparison.md` |

## How to run it

One-time setup:

1. Repository secret `ANTHROPIC_API_KEY`. It is passed only to the agent step.
2. A GitHub App for the commits (Settings, Developer settings, GitHub Apps, New): repository permissions **Contents: Read and
   write**, **Pull requests: Read and write**, no webhook. Install it on this repository only. Store its id as the secret
   `AGENT_APP_ID` and the downloaded private key (the whole `.pem`) as `AGENT_APP_PRIVATE_KEY`. Without them the agent says so
   in a comment and stops before spending anything.
3. Optional repository variables: `CLAUDE_MODEL`, `AGENT_MAX_TURNS` (default 60), `ANALYSIS_MAX_TURNS` (30), `ANALYSIS_MAX_DIRS` (5), `AGENT_AUTO_ANALYSIS` (`0` turns the automatic analysis off), `AGENT_AUTO_WRITE` (`0` turns automatic writing off), `AGENT_AUTO_WRITE_MAX` (3), `AGENT_SUBPROCESS_SCRUB` (set `0` only to
   run without the subprocess scrub).
4. Merge to the default branch. `issue_comment` workflows and `.claude/` are read from there. Optionally run `Warm caches` once.

The analysis needs only `ANTHROPIC_API_KEY`; without it the run is skipped with a notice. Using it, in a pull request from a branch of this repository (the analysis comment appears by itself; the commands below act on it):

| Comment (the whole comment, one line) | Effect |
|---|---|
| `agent coverage` | tests for the directories changed in the PR |
| `agent coverage modules/<name>` | tests for one directory, changed or not |
| `agent check comments` | read unresolved review threads on test files, change the tests or decline with a reason, reply, resolve what was addressed |
| `agent remove <sha>` | revert one commit made by the agent |

Locally: `scripts/test-guards.sh` runs the tests of the deterministic scripts (command grammar, path guard, commit and revert
rules, thread handling with a stubbed `gh`, quality checks).

## Example run

**Pull request 7:** https://github.com/andrey-parkhomets/tf-platform-base/pull/7 (kept open on purpose, so the conversation and
the commits stay visible). The change: `modules/log-analytics-workspace/variables.tf` gets a `validation` on `retention_in_days`
(30 to 730). The module had no tests. Everything below happened on GitHub with the real `claude-code-action`, model
`claude-haiku-5-5`, the GitHub App `andrey-tf-test-agent`.

| Step | What happened |
|---|---|
| PR opened | `terraform-checks.yml`: detect, lint, Checkov and verify passed. One hint comment: "`modules/log-analytics-workspace` has no tests", with the list of commands. No model was involved |
| Comment `agent coverage` | Decision `created` (skills `tf-change-analysis`, `terraform-test`, `tf-test-writing`, `tf-test-verify`, `tf-review-findings`). Seven `run` blocks: SKU and inputs, default retention, retention reaches the resource, the upper bound accepted, values below 30 and above 730 rejected with `expect_failures`, tags. The verify job (no secrets) re-ran them: fmt, init, validate pass, **7 passed, 0 failed**, mutation check 2 of 2 caught. The `commit` job pushed commit `d0d0c27` as `andrey-tf-test-agent[bot]`; the PR checks then ran on it like on any commit. About 3 minutes in total |
| Findings in the report | medium: the workspace keeps shared-key authentication enabled, unlike `storage-account`; low: `name` is not validated; info: the 30 to 730 range was taken from the code, not checked against Azure documentation. No infrastructure file was touched |
| Inline review comments on the test file, then `agent check comments` | Two threads. (1) "add a run that sets the lower bound 30 explicitly": the agent added `retention_accepts_the_lower_bound`, verification passed, commit `65e9930`, the thread was answered ("Addressed in 65e9930 ...") and **resolved**. (2) "make this an apply-mode test against a real workspace": **declined** with a reason (offline plan-mode tests only), reply posted, thread left **open** for a person |
| Comment `agent remove 65e9930` | A revert commit `a57b5e7` by the App, no model involved |
| Comment `agent remove ea32d26` (a human commit) | Refused with "was not made by the agent; revert it yourself", nothing pushed |

Other runs behind the design: the earlier, automatic version of the workflow on pull request 2 (`private-endpoint`, 9 tests, see
`docs/lessons-from-github-runs.md`) and local runs against a `function-app` change including an injection attempt in the diff
(ignored and reported as a high finding, see `docs/model-comparison.md`).

## What the generated tests can and cannot show

They show: the module sets the arguments it is supposed to set (TLS, public access, identities, names), variable validations
accept and reject the right values, `for_each` and conditional resources expand as intended, inputs reach the right resources,
and a later change does not silently remove those properties.

They do not show: that Azure accepts the configuration (SKU, region, name rules, quotas, policy), anything the provider computes
(ids, IP addresses and principal ids are generated by the mock), runtime or network behaviour, RBAC actually working, cross-module
wiring in a real environment, or that a security default is **right**. A test written from the code can encode a mistake in the
code, so the agent is told not to bless insecure behaviour (for example `ftps_state = "AllAllowed"`) and to raise it as a finding.

## Assumptions

- Terraform >= 1.9, `azurerm ~> 4.0`, a public GitHub repository, pull requests from branches of the same repository.
- Reviewers read the comment and the commit. Findings are information, not a gate.
- One module or stack per directory under `modules/` and `stacks/`; no nested modules.
- The `ANTHROPIC_API_KEY` belongs to a workspace with a spend limit. The GitHub App is installed on this repository only.
- Stacks are treated like modules by the tooling, but their tests are out of scope for now: without integration tests they add
  little beyond the module tests.

## Limitations

- The automatic analysis (`agent-analysis.yml`) has not run on GitHub yet: it is new, it lives on the default branch only after
  merge, and `pull_request_target` workflows are read from there. The renderer is tested locally (`scripts/test-guards.sh`) and the
  workflow passes `actionlint`; the first real run is the next example to add. It also does not receive the Checkov SARIF.
- The comment-driven flow is covered locally by `scripts/test-guards.sh` (the scripts) and on GitHub by the real run on pull
  request 7. There is no local simulation of the workflows. Not yet exercised on GitHub: a branch that moves during a run, and a
  fork pull request (refused by design).
- Fork pull requests get no agent run, by design.
- Automatic writing means `terraform test` on pull request code runs next to the model key for every same-repository PR the
  analysis flags, without a person typing a command. Opening a PR from a branch already needs write access, which is the same
  population that could comment the command, but it removes the human step. Accepted for this repository.
- The agent job runs `terraform test` on pull request code next to the model key. The key is removed from the environment of
  those processes (subprocess scrub plus bubblewrap) and `GITHUB_TOKEN` is read-only, but `data "external"` can run a script at
  plan time. The boundary that matters is: same repository, write permission, and no write token in this job. Accepted for this
  repository.
- The agent can still write weak or wrong tests. The guards catch structure, the mutation check catches some weakness, a reviewer
  catches the rest.
- A branch that moves while the agent works makes the push fail; the command has to be repeated (nothing is forced).
- Checkov scans the whole repository; SARIF is not uploaded to code scanning.
- A prompt-injection attempt in the diff or in a review comment is handled by the rules in the agent file, the tool allow-list and
  the guard. None of these is a proof.

## Many more modules, teams or repositories

- One shared repository for the agent, skills and workflows, called as reusable workflows, so a change to a skill is one PR.
- Matrix limit is 256 legs: batch by team or directory count and cap spend per run.
- Per-repository `.claude/skills/` overlays on a shared baseline.
- Shared runner pool with warm provider and CodeGraph caches; the App installed per organisation with a token per repository.
- Metrics: how often the agent is asked, commits kept versus reverted, mutants caught, threads resolved, false findings.

## For a production version

- Enforce the hint: require `agent coverage` (or an explicit waiver) for changed modules without tests, as a required check.
- Evaluation suite: a fixed set of changes with expected tests and findings, scored on every model or prompt change.
- Federated short-lived credentials for the model API, an egress allow-list on the runner, and Terraform for the agent in a
  container without the key.
- Signed commits through the API and branch protection that requires `verify`; Dependabot for action SHAs; a scheduled `Warm caches`.
- Per-PR token budget and skipping drafts. Checkov SARIF to code scanning on changed paths with a baseline.
- Integration tests (`terraform test` with real resources) in an ephemeral subscription on merge, outside this offline workflow.

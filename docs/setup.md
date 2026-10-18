# Setup in detail

The full setup behind the short list in `SOLUTION.md`.

One-time setup:

1. An environment `tf-ai-agent` that only the default branch can use, holding three **environment secrets**: `ANTHROPIC_API_KEY`
   (read only by the jobs that run the model), and `AGENT_APP_ID` and `AGENT_APP_PRIVATE_KEY` of a GitHub App (read only by the jobs
   that push). Delete any repository-level copies: a repository secret can be read by a workflow edited on a branch, an environment
   secret cannot. Set the environment secrets before the first run (jobs in reusable workflows read nothing else); commands, order and the check: `docs/secrets-environment.md`.
2. The GitHub App for the commits (Settings, Developer settings, GitHub Apps, New): repository permissions **Contents: Read and
   write**, **Pull requests: Read and write**, no webhook. Install it on this repository only. Without its secrets the comment
   commands say so and stop before spending anything.
3. Merge to the default branch. `issue_comment` and `pull_request_target` workflows and `.claude/` are read from there. Optionally
   run `tf-cache-warm` once (it warms the provider and pre-commit caches; there is no CodeGraph cache).
4. **Before 2 November 2026:** create an Actions event policy that allows the events the workflows use, `pull_request_target`
   included. From that date GitHub blocks `pull_request_target` in public repositories without one, which would stop the automatic
   analysis. Exact settings and how to check them in Evaluate mode: `docs/actions-policy.md`.
5. Optional repository variables: `CLAUDE_MODEL` (both stages), `ANALYSIS_MODEL` and `WRITER_MODEL` (one stage each, they win over `CLAUDE_MODEL`), `AGENT_MAX_TURNS` (60), `ANALYSIS_MAX_TURNS` (30), `ANALYSIS_MAX_DIRS` (5),
   `AGENT_AUTO_ANALYSIS` (`0` switches the analysis off), `AGENT_AUTO_WRITE` (`0` switches automatic writing off for the repository; unset
   or anything else = on), `AGENT_AUTO_WRITE_MAX` (3), `AGENT_SUBPROCESS_SCRUB` (`0` only to run without the subprocess scrub). Create the
   labels `no-auto-pr-agent` (switch a PR off) and `auto-pr-agent` (opt a PR back in when the repository variable is `0`).

Using it, in a pull request from a branch of this repository: the checks and the analysis comment appear by themselves, and the agent
commits tests when it decides they are needed (unless switched off). Comment commands (the whole comment, one line, from someone with write access):

| Comment | Effect |
|---|---|
| `agent coverage` | tests for the directories changed in the PR (not limited by the cap) |
| `agent coverage modules/<name>` | tests for one directory, changed or not |
| `agent check comments` | read unresolved review threads on test files, change the tests or decline with a reason, reply, resolve what was addressed |
| `agent remove <sha>` | revert one commit made by the agent |

Locally: `scripts/test-guards.sh` tests the deterministic scripts (command grammar, path guard, commit and revert rules, review
threads with a stubbed `gh`, test-quality checks, automatic-write selection, comment rendering, workflow naming rules).

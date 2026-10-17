# What the first runs on GitHub showed

These runs were made with the first, automatic version of the workflow (the agent started on every pull request and the tests were shown as a patch). The `act` simulation mentioned below has since been removed; the lessons about it, the docs action and the turn limit still apply. `act` could not prove everything, and the first real runs found three things it had missed. They are recorded here because they
are the honest answer to "how much does a local simulation tell you".

| Run | Finding | Fix |
|---|---|---|
| Pull request 1 (the pull request that added the tooling) | The docs check failed. `terraform-docs/gh-actions` bundles terraform-docs v0.20.0 and has no input to choose another version; I had generated the READMEs with v0.24.0, which writes different table separators. `act` could not catch it because it cannot run that Docker action and my stand-in used the newer binary | READMEs are regenerated with the action's own image (command in the README); the `act` stand-in uses v0.20.0 |
| Pull request 2 (the example pull request) | Bubblewrap installed and its preflight passed on the hosted `ubuntu-24.04` runner, so the agent ran with the subprocess scrub on. The run then failed because the agent took 44 turns and the limit was 40: the action treats exceeding `--max-turns` as an error even when the model reports success | The turn limit is now the repository variable `AGENT_MAX_TURNS` (default 60). The guard, patch collection and upload now run even when the agent step fails, so tests already written are still verified and shown |
| Pull request 2 | The comment said the agent definition was not on the base branch, which was wrong: the agent step had failed | The collect step now records why the agent did not run; the comment distinguishes "definition not on base yet", "agent step failed" and "skipped for fork or bot" |

Two points worth keeping: the verify job and the report still produced a correct, honest result when the agent step failed (the PR got a
comment and a pass/fail for the module), which is the property the split into separate jobs is for; and the Claude Code subprocess scrub
works on a GitHub-hosted runner without any special runner setup beyond installing bubblewrap and socat.


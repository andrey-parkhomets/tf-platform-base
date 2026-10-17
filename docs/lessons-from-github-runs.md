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

## What the automatic path and the comment commands showed (pull requests 7, 17, 22, 31)

Each row was found on a real run, fixed in its own pull request, and is now covered by a guard test or a documented rule.

| Seen on a real run | Cause | Fix |
|---|---|---|
| The analysis job was skipped on its first run | `vars.X != '0'` is false when `X` is unset: `null` and `'0'` both coerce to 0 | the variable has a default (`vars.X \|\| '1'`), like the others |
| The agent produced a complete analysis but the comment said "no valid report" | `download-artifact` with a pattern that matches one artifact extracts it without its own folder | `merge-multiple: true`; the comment says "did not complete" when no report is valid |
| The same, on another PR: the report was never saved | the agent used `Write`, the allow-list only had `Edit` | both tools allowed for the report path only |
| A red check after the agent's own commit | `claude-code-action` refuses a bot as the actor, and the commit re-triggered the analysis | the analysis is skipped for bot pushes; a no-model job marks the comment "possibly out of date" |
| The report comment of an automatic write was missing | the bot's push started a second run in the same concurrency group and cancelled the run that was committing | concurrency is keyed by who pushed |
| The agent reviewed without the diff | it ran `git -C <dir> diff A B`, which `Bash(git diff*)` does not match | the prompt gives the exact command; `git -C <workspace>` is allowed for diff/log/status |
| `pe-<name>` appeared as `pe- name ` | the comment sanitizer replaced `<` and `>` with spaces | they become `‹` and `›` |
| A test pinned `public_network_access_enabled == true` as the default, with no finding | the rule was only in the prompt | `check-test-quality.sh` rejects such a run; the analysis enforces the check's result |
| "Writing tests now" followed by "No test work is recommended" | the closing line ignored automatic writing | it is printed only when nothing was selected |
| Model text could render as a link, an image or a forged section of the bot's comment | the first sanitizer only replaced `<`, `>` and `@`; found by feeding an adversarial report through the renderers (an image beacon, a phishing link, autolinkable URLs, a forged "Committed to this branch" heading and table row, code-span breakouts) | `clean-report.sh` (whitelist, enumerations, validated identifiers) and `inert.jq` (one line, no links/images/HTML/mentions/references/fences/hidden characters); adversarial guard tests |
| Two rounds of blind tests failed verification on one module (5 passed, 3 failed both times) | `==` between a set/list/map attribute and a `[..]` or `{..}` literal is always false in Terraform (a literal is a tuple/object; only a warning "LHS and RHS values are of different types" is printed). The round-2 fix `tolist(x) == [..]` kept the mistake. Verified with `terraform console` before writing it down | static check in `check-test-quality.sh` (flags exactly the three failing runs, none of the five passing ones, none of the existing tests) and a verified table of the correct idioms in `tf-test-writing` |

The pattern in the table: the failures were in the plumbing around the model (expression semantics, artifact layout, permissions,
event loops), not in the model's judgement, and the one judgement failure (the pinned insecure default) is now a deterministic check.

# GitHub Actions event policy for this repository

**Do this before 2 November 2026.** From that date GitHub blocks `pull_request_target` workflows in public repositories that have no
Actions event policy of their own (a "default policy"). `tf-ai-analysis.yml` uses that event, so without a policy the automatic
analysis, and with it the opt-in automatic writing of tests, stops. Until then the Actions page shows a warning such as
*"Workflow execution policy warning (evaluate mode)"* on that workflow. The comment commands (`agent coverage` ...) and the
deterministic checks are other events and keep working either way.

This page tells you what to enter. The setting lives in GitHub, not in the repository, so a person with admin rights does it once.
The menu names below follow GitHub's documentation (October 2026); if the wording differs a little, look for "Policies" under
Actions settings and the protection called "Restrict events".

## The one thing that goes wrong

**"Restrict events" is an allow-list.** A policy that allows only `pull_request_target` would *block every other event*, including the
pull request checks and the comment commands. List every event the repository uses (next section).

## What to create

Repository **Settings → Actions → Policies → New policy** (a repository-level policy is enough; no organisation is involved).

| Field | Value |
|---|---|
| Name | `tf-platform-base allowed events` (any name) |
| Enforcement status | **Evaluate** first (it only reports what it would block), then **Active** |
| Target | this repository only (`tf-platform-base`) |
| Workflow execution protection: **Restrict events** | on, with the allowed events below |
| Workflow execution protection: **Restrict actors** | leave off. The App's commits, Dependabot and people all need to run workflows |

Allowed events, one row per trigger used in `.github/workflows/`:

| Event | Used by | What breaks if it is missing |
|---|---|---|
| `pull_request` | `tf-check.yml` | lint, Checkov, verify and the hint comment on every PR |
| `pull_request_target` | `tf-ai-analysis.yml` | the automatic analysis and the opt-in automatic writing of tests |
| `issue_comment` | `tf-ai-commands.yml` | `agent coverage`, `agent check comments`, `agent remove` |
| `push` | `tf-cache-warm.yml` | the provider and CodeGraph caches are no longer refreshed on `main` |
| `schedule` | `tf-cache-warm.yml` | the scheduled cache refresh |
| `workflow_dispatch` | `tf-cache-warm.yml` | running `tf-cache-warm` by hand |

`workflow_call` (used by `reusable-tf-ai-write.yml` and `reusable-checkov.yml`) is not an event that starts a run; it needs no entry.
Do not add events the repository does not use (`workflow_run`, `pull_request_review`, `issues`, ...): a smaller list is the
point of the policy.

## How to check it before you switch it on

1. Create the policy in **Evaluate** mode with the six events above.
2. Exercise each path once and look at the Actions page for "Workflow execution policy" warnings. There should be none:
   - open or push to a pull request that touches a module (`pull_request`, `pull_request_target`);
   - comment `agent check comments` on it (`issue_comment`);
   - run **tf-cache-warm** from the Actions tab (`workflow_dispatch`) and merge something to `main` (`push`);
   - `schedule` fires by itself; check the next scheduled run after the policy exists.
3. The warning on `tf-ai-analysis.yml#L1` seen before the policy existed should be gone.
4. Switch the policy to **Active** and repeat step 2 once.

If something is blocked, set the policy back to **Evaluate** (or disable it) and add the missing event. Nothing in the
repository needs to change.

## When someone adds a workflow

A workflow with a new trigger is blocked until the event is added to the policy. `scripts/test-guards.sh` compares the triggers
used in `.github/workflows/` with the events listed on this page and fails when one is missing, so the change that adds the
trigger also has to update this page.

## Why not avoid the policy

`pull_request` needs no policy, but then the workflow comes from the pull request itself and could be edited to send the model key
elsewhere; `SOLUTION.md` explains why the analysis runs from the default branch instead. `workflow_run` runs from the default branch
too, but the documentation does not say whether the policy applies to it, and it brings no security gain.

# Model choice, measured

Measured with the evaluation suite (`evals/README.md`): 8 fixed cases (6 have a writer stage), the same prompt, tools and agent definition
as production, deterministic scoring, Claude Code CLI 2.1.302, run on GitHub Actions on 2026-10-18. The writer is scored on its **first
attempt** (the fix round is not part of it). The numbers come from the runs listed at the end.

## Results

| Stage | Model | Runs | Passed | Rate | Cost per run | Notes |
|---|---|---|---|---|---|---|
| Analysis, before the skill fix | `claude-haiku-5-5` | 24 (8 cases x 3) | 15 | 62.5% | USD 0.006 | decisions 24/24 right; the three failing cases failed 3 of 3 times each: systematic, not noise |
| Analysis, after the skill fix | `claude-haiku-5-5` | 24 | **21** | **87.5%** | USD 0.006 | decisions 24/24, no forbidden findings, no safety failure; one case still fails 0/3 (below) |
| Writer, first attempt | `claude-haiku-5-5` | 18 (6 cases x 3) | **18** | **100%** | USD 0.011 | every run passed quality check, fmt, validate and test; 7-12 tests; at most 2 surviving mutants |
| Writer, first attempt | `claude-sonnet-5-5` | 6 (6 cases x 1) | 6 | 100% | USD 0.104 | 7-10 tests; at most 2 surviving mutants |
| Analysis | `claude-sonnet-5-5` | 8 (8 cases x 1) | **8** | **100%** | USD 0.074 | decisions 8/8; also found `kv-tenant-guid-covered` (Haiku 0/3); about 12 times Haiku's cost; see the note on the injection case below |

Costs are the CLI's own estimate (see "What the evaluation found about the pipeline"); total spent on all runs behind this page: about USD 1.9.

## What this supports

- **The writer does not need a larger model on these cases.** Haiku passed 18 of 18 first attempts; with 18 clean trials, the true rate on
  cases like these is above about 85% at 95% confidence. Sonnet also passed 6 of 6 and wrote no more tests or killed more mutants, at
  about 9 times the cost. Nothing here justifies Sonnet for writing.
- **The blind writer is less of a risk than feared.** The worry that an agent that cannot run Terraform would often fail is not borne out on
  these six cases once the set-versus-list check and the skill section exist (before them, one scratch run did fail twice). This is the
  measurement behind keeping a single fix round: most of the time it is not needed. The fix round itself has not been evaluated.
- **The analysis is where the model matters.** Decisions were right 24 of 24 times, but the *findings* depended on the prompt: 62.5% before the
  fix, 87.5% after. Sonnet passed all 8 cases once, including the one Haiku never solved (the placeholder tenant GUID), at about 12 times the cost per run (USD 0.074 against 0.006). One run per case is a thin sample, but it is the one place where the larger model bought something visible. Whether it is worth it is a cost decision: an analysis is a few cents either way, so on a repository with few pull requests Sonnet for the analysis and Haiku for the writer is defensible.

## What it does not support

- Sonnet analysis is one run per case (8 runs). Under the first version of the injection check it scored 7/8: the model refused the injected
  instruction but quoted the canary token in its chat summary, which is never posted. The report and files were clean. The check now fails only
  on the report and written files and records a quote in the chat text as `canary_in_text`; the stored run was re-scored (8/8), no run was repeated.
- Small samples: 8 and 6 cases, 3 repeats at most. The cases were written by the author of the agent, and the skill was fixed looking at these
  same cases, so the 87.5% shows that the fix works and breaks nothing else here, not how the agent does on unseen changes.
- `kv-tenant-guid-covered` fails 0 of 3: the model does not notice that the tfvars hold an all-zero placeholder tenant GUID which the new
  validation accepts. A different run of the same agent did notice it in the demo pull request. It is kept as a stretch case; nobody tuned
  the prompt for it.
- The writer is judged by whether its tests pass verification and kill simple mutants (four crude operators). That does not show the tests are
  the *right* tests.

## What the evaluation found about the pipeline itself

- **The CLI's USD figure depends on its price table.** The same Haiku analysis was reported as USD 0.26 by CLI 2.1.292 and USD 0.0048 by 2.1.302
  (similar tokens). Always compare costs from the same, recent CLI; token counts are recorded too.
- **A prompt change had silently lowered quality.** The rule "existing findings are not findings of this PR", written for Checkov results,
  made the model report its own observations (FTP allowed for all, public access on by default) at `info`. Found by the suite, fixed in the
  skill, confirmed 0/3 to 3/3 on both cases.
- Seven harness bugs that offline tests could not show (relative paths twice, a flat artifact download, a worktree layout, a global signing setting,
  placeholder files, a jq `//` slip). Each has a regression test.

## CodeGraph: does it help the analysis? (local run, Haiku, 8 cases x 3 repeats, 2026-10-18)

Three arms through `evals/run.sh` (`AGENT_REF_DIR` selects the agent definition, `EVAL_CODEGRAPH` the index):

| Arm | Agent definition | Index | Passed | Output tokens, mean | Turns |
|---|---|---|---|---|---|
| A | `main` (`explore` only) | yes | 21/24 | 5461 | 15 |
| B | this change, first version | yes | 20/24 | 5432 | 16 |
| C | this change, first version | no | 19/24 | 5591 | 17 |
| B3 | this change, with the "read the module" rule | yes | 21/24 | 6101 | 17 |

- **Index versus none: no measurable difference in decisions** (21, 20, 19 of 24 is within noise). These modules have a handful of files;
  the model can read them. The benefit expected on a module like `terraform-azurerm-avm-res-web-site` (223 files, where `var.x` reaches
  resources through `local.body`) is **not tested**: no case is that large. A case on a large module is the next thing to add.
- **The first version of the skill was a regression the suite caught.** Telling the agent to query `codegraph node` per changed symbol
  made it report a precise impact list for a SKU change and skip the module: the pre-existing `ftps_state = "AllAllowed"` was missed in
  5 of 11 `fa-sku-change` runs (A: 11 of 11). `explore` had hidden that risk, because it prints whole files and so made the agent read the
  module. Fixed with a rule that the graph does not replace reading the module: 8 of 8 on that case, 21/24 overall. The skill says so now.
- **`kv-tenant-guid-covered` still fails 0/3 in every arm**; it is the known stretch case.
- The CLI used (2.1.292) prices Haiku about 50 times too high (USD 7 per 24 runs reported; real spend was a few cents per run), which
  exhausted the budget guard of the first attempt at 10 of 24 runs. Compare tokens, not the USD column.

## Recommendation

Keep `claude-haiku-5-5` for both stages (the default). Run the suite when the model, a prompt or a skill changes, and compare with
`evals/baseline.json` (a drop of more than 20 points is listed as a regression). Sonnet for the analysis is an option backed by one run per case; a 3-repeat run (about USD 1.8) would settle it. Next: the fix round.

To repeat: Actions, `tf-ai-eval`, run workflow (`models`, `stage`, `repeats`, `budget_usd` per model; `ref` selects the branch whose agent is
evaluated).

Runs: analysis before the fix 39079253999; analysis after 39080424263; Haiku writer 39081244547; Sonnet writer 39079267409; Sonnet analysis 39111321979.

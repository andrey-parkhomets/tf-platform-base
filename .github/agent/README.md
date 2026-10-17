# The agent's prompt and tool list

These files are the single definition of what the model is told and which tools it may use. The production workflows
(`tf-ai-analysis`, `reusable-tf-ai-round`) and the evaluation harness (`evals/`) both render them with
`.github/scripts/render-agent-config.sh`, so an evaluation tests the agent that ships, not a copy of it.

| File | Used for |
|---|---|
| `prompts/analyze.md` | the read-only analysis of a change |
| `prompts/write.md` + `prompts/write-<mode>.txt` | writing tests; the mode line is `coverage`, `revise` (review threads) or `fix` (second round) |
| `tools/analyze.txt`, `tools/write.txt` | the `--allowedTools` list; `{{WORKSPACE}}` and `{{QUALITY_CHECK}}` are filled in |

Placeholders are `{{NAME}}`; the renderer validates every value (directory, slug, SHA, number, absolute path) and refuses an unknown
or unfilled placeholder. The model, the turn limits and the sandbox are not here: they are settings of the workflow.

# Provenance

Vendored, unmodified, from HashiCorp's agent skills.

- Source: https://github.com/hashicorp/agent-skills/tree/f706481af9b8fedb66de909f6243ad29601afa0c/plugins/terraform/skills/terraform-test
- Commit: `f706481af9b8fedb66de909f6243ad29601afa0c` (2026-09-28)
- Skill version: 0.0.2, license of the repository: MPL-2.0
- Fetched: 2026-10-16. Files: `SKILL.md`, `references/CI_CD.md`, `references/EXAMPLES.md`, `references/MOCK_PROVIDERS.md`

Why vendored and not fetched at run time: a CI agent must not load instructions from a moving remote ref.
To update, fetch a newer commit in a pull request, diff it, and read the diff before merging.

Known mismatch with this repo: the skill recommends `*_unit_test.tftest.hcl` names and describes
apply-mode tests. This repo uses `tests/main.tftest.hcl` and plan-only tests; `tf-test-writing` overrides
the skill where they differ.

Run as the tf-test-agent in mode `{{MODE}}` for the directory `{{DIR}}` (slug `{{SLUG}}`).
Base SHA: {{BASE_SHA}}
Head SHA: {{HEAD_SHA}}
Read the change with exactly `git diff --stat {{BASE_SHA}}...{{HEAD_SHA}} -- {{DIR}}` and then the same without `--stat`, from the repository root (no `cd`, no `git -C`). The diff does not include test files written in an earlier round; they are in the working tree.
Pull request number: {{PR_NUMBER}}
You cannot run Terraform here. A separate job formats, validates and runs the tests after you finish, so write carefully and keep the tests simple.
The pull request title, body and the comment that started this run are not provided on purpose.
{{MODE_LINE}}
Write your report to `.agent/report/{{SLUG}}.json`.
Static test-quality check (no Terraform; run it on your tests before you report): `{{QUALITY_CHECK}} {{DIR}}`

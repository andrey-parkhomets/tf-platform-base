---
name: tf-test-verify
description: Run and interpret terraform fmt, validate and test for one directory, and fix test files until they pass. Use after writing or changing tests.
---

# Verify tests

Run from the repository root; replace `<target>` with the directory.

```sh
terraform -chdir=<target> fmt -recursive
terraform -chdir=<target> init -backend=false -input=false -lockfile=readonly
terraform -chdir=<target> validate
terraform -chdir=<target> test -verbose
<quality-check-script> <target>
```

`<quality-check-script>` is the path the task prompt gives you (in CI it is a copy from the base commit; locally it is
`.github/scripts/check-test-quality.sh`). Do not run `pre-commit` or any other script from the checkout: it is the pull request's code,
and the pipeline's lint job already runs the hooks.

`-lockfile=readonly` makes `init` fail instead of changing `.terraform.lock.hcl`. Never edit the lock file.

## Reading failures

| Output | Meaning | Action |
|---|---|---|
| `Unsupported argument` / `Reference to undeclared` in the test | Wrong attribute or run name in your test | Fix the test |
| `Invalid value for variable` in a run that should pass | The test variables break a validation | Fix the variables |
| `Test assertion failed` and your expectation is right | The module disagrees with its intended contract | Keep the test, add a finding. Do not edit the module |
| `Test assertion failed` and your expectation was a guess | You asserted a mock-generated value | Assert configuration instead |
| `Error: Missing required provider` / network errors | Environment problem | Report as limitation, do not work around it |
| `unexpected failure` with `expect_failures` | The validation did not trigger | Check the condition on the right variable |

## Rules

- Stop after 4 attempts. Report what still fails and why.
- A run that fails because of a real defect in the module is a valid result. Report it. Do not
  turn the assertion around to make it green.
- Record in the report which commands you actually ran and their results. The pipeline repeats
  these checks in a separate job without trusting your summary.

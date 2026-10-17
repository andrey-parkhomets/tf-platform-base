---
name: tf-test-writing
description: Repository-specific rules for writing terraform test files in this repo (mock providers, plan mode, layout, quality bar). Use together with the terraform-test skill, which holds the general syntax.
---

# House rules for tests in this repo

> **You cannot run Terraform in this pipeline** (not installed in your job, no command allowed). Everything the general
> `terraform-test` skill says about running `terraform test` is done for you by a separate job after you finish; you get one more
> round with its log if it fails. So: keep tests small, copy the shape of the existing tests in the repository, and re-read each
> `run` against the module before you report.

Read the `terraform-test` skill first for syntax. This skill only adds what is local, and where the
two disagree, **this skill wins** (the baseline skill covers apply-mode integration tests that this
repo does not allow).

## Layout and naming

- One file per module: `modules/<name>/tests/main.tftest.hcl`. Add more files only when a module has
  clearly separate concerns, named `<topic>.tftest.hcl`. (Not the `*_unit_test` naming from the baseline.)
- Model new tests on `modules/storage-account/tests/main.tftest.hcl`.

## Offline rules

- Every file starts with `mock_provider "<name>" {}` for each provider the module uses
  (`azurerm`, and `external` for `function-app`).
- `command = plan` only. Never `apply`. Terraform `>= 1.9`, so `state_key` and `parallel` are allowed
  but rarely needed.
- A mock provider returns generated values for computed attributes. Do not assert on computed values
  that the mock invented (ids, principal ids). Assert on what the module configures: arguments, counts,
  `for_each` keys, and wiring between resources.
- Data sources: mocked providers return random strings. If the module output depends on a data source
  (`function-app`'s `data.external.build_info`), use `mock_data` or `override_data` with a fixed result
  so the test is deterministic. Mocking `external` also means the script `scripts/build-info.sh`
  is never executed by the test.

## Comparing values (Terraform types): the mistake you cannot see

Provider attributes are collections: `set(string)`, `list(string)`, `map(string)`. A literal `[...]` is a **tuple** and a literal
`{...}` is an **object**. In Terraform `==` between values of different types is simply `false`; the run only prints the warning
"LHS and RHS values are of different types", and your test fails with a message that looks like a wrong value. This is checked in
Terraform 1.15 and holds for a `list(string)` as well as a set or a map, so converting the attribute with `tolist()` does **not** help.

| Do not write | Write one of |
|---|---|
| `x.subresource_names == ["blob"]` | `contains(x.subresource_names, "blob")`, `one(x.subresource_names) == "blob"`, `length(x.subresource_names) == 1`, or `x.subresource_names == toset(["blob"])` |
| `tolist(x.zone_ids) == ["a"]` | `tolist(x.zone_ids) == tolist(["a"])`, or `tolist(x.zone_ids)[0] == "a"` |
| `x.tags == { env = "dev" }` | `x.tags["env"] == "dev"`, or `x.tags == tomap({ env = "dev" })` |
| `x.items == []` | `length(x.items) == 0` |

Rule of thumb: compare an element (`contains`, `one`, an index, a key, `length`), or convert the **literal** to the attribute's type
(`toset`, `tolist`, `tomap`). Never put a bare `[...]` or `{...}` on the right of `==` or `!=`.
`check-test-quality.sh` rejects it statically, and you can run it before you report.

## What to cover

- Defaults that matter for security (TLS version, public access, network default action, HTTPS only).
- Every `validation` block: one passing and one failing case (`expect_failures = [var.x]`).
- Conditional and `for_each` resources: zero, one and several elements.
- Outputs and cross-resource references the callers depend on.
- Tags and naming patterns derived from inputs.

## Quality bar (checked by `.github/scripts/check-test-quality.sh`)

- Every `run` block has at least one `assert` or `expect_failures`.
- No constant conditions such as `condition = true`.
- Error messages say what is wrong and what was expected.
- A test must be able to fail. After writing it, ask "what change to the module would make this fail?"
  If nothing, the test is decoration. Delete it or sharpen it.
- Do not weaken or delete an existing assertion to make a run pass. Report a finding instead.

## Insecure current behaviour

If the module's current behaviour is insecure (for example `ftps_state = "AllAllowed"`), do **not** write a
test that blesses it as correct, and do not write a failing test for the desired state either.
Write tests for what the module is supposed to guarantee, and put the insecure setting in the findings.
`check-test-quality.sh` enforces this for a list of settings (public network access, TLS below 1.2, `AllAllowed` FTPS, shared keys, and so on):
a run that asserts the insecure value without setting that input itself fails the check. Testing that an input you set is
*honoured* is fine; pinning the *default* is not.

This also applies to **defaults**. Do not write a test that asserts an unsafe default value (for example
`public_network_access_enabled == true` when the variable is not set); that pins the risk in place and makes a later fix
look like a regression. Test that the input is honoured instead (set it to `false`, assert `false`), and report the
unsafe default as a finding.

## Cover what a mutation would change

A later check breaks the module code in small ways (a string literal, a name prefix, a dropped tag) and
expects at least one test to fail. So besides behaviour, assert the resource `name` built from the
module's inputs and the `tags` the module sets or merges. If a value is only a mock-generated one, say so
in the report instead of asserting it.

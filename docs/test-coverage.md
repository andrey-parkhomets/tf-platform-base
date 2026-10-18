# Test coverage of the modules

Plan-mode `terraform test` runs (mock provider, no credentials) per module. Counts are `run` blocks.

| Module | Runs before | Runs after |
|---|---|---|
| `data-factory` | 6 | (not changed) |
| `databricks-workspace` | 0 | |
| `function-app` | 9 | (not changed) |
| `key-vault` | 2 | |
| `log-analytics-workspace` | 0 | |
| `network` | 3 | |
| `private-endpoint` | 0 | |
| `storage-account` | 12 | (not changed) |

`stacks/data-platform` has no tests on purpose: it has no logic of its own, and a test of a tfvars value would bless it.

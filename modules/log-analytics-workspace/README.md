# log-analytics-workspace

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | 4.81.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region. | `string` | n/a | yes |
| name | Workspace name. | `string` | n/a | yes |
| resource\_group\_name | Resource group that holds the workspace. | `string` | n/a | yes |
| retention\_in\_days | How long logs are kept. | `number` | `30` | no |
| tags | Tags for all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the workspace. |
<!-- END_TF_DOCS -->

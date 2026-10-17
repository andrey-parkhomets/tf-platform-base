# function-app

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| azurerm | ~> 4.0 |
| external | ~> 2.3 |

## Providers

| Name | Version |
| ---- | ------- |
| azurerm | 4.81.0 |
| external | 2.4.2 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_linux_function_app.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_function_app) | resource |
| [azurerm_role_assignment.runtime_storage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_service_plan.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/service_plan) | resource |
| [external_external.build_info](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| app\_settings | Application settings. | `map(string)` | `{}` | no |
| location | Azure region. | `string` | n/a | yes |
| name | Function app name. | `string` | n/a | yes |
| public\_network\_access\_enabled | Allow access to the app from the public internet. | `bool` | `true` | no |
| python\_version | Python version of the runtime. | `string` | `"3.12"` | no |
| resource\_group\_name | Resource group that holds the function app. | `string` | n/a | yes |
| storage\_account\_id | ID of that storage account. | `string` | n/a | yes |
| storage\_account\_name | Storage account the function app uses for its runtime. | `string` | n/a | yes |
| tags | Tags for all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| id | ID of the function app. |
| principal\_id | Object ID of the app's managed identity. |
<!-- END_TF_DOCS -->

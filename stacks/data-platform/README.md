# data-platform

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | ~> 2.3 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.81.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_data_factory"></a> [data\_factory](#module\_data\_factory) | ../../modules/data-factory | n/a |
| <a name="module_data_lake"></a> [data\_lake](#module\_data\_lake) | ../../modules/storage-account | n/a |
| <a name="module_databricks"></a> [databricks](#module\_databricks) | ../../modules/databricks-workspace | n/a |
| <a name="module_function_app"></a> [function\_app](#module\_function\_app) | ../../modules/function-app | n/a |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | ../../modules/key-vault | n/a |
| <a name="module_key_vault_endpoint"></a> [key\_vault\_endpoint](#module\_key\_vault\_endpoint) | ../../modules/private-endpoint | n/a |
| <a name="module_lake_endpoint"></a> [lake\_endpoint](#module\_lake\_endpoint) | ../../modules/private-endpoint | n/a |
| <a name="module_log_analytics"></a> [log\_analytics](#module\_log\_analytics) | ../../modules/log-analytics-workspace | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../../modules/network | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_data_lakes"></a> [data\_lakes](#input\_data\_lakes) | Data lake storage accounts by short key, with their containers. | <pre>map(object({<br/>    containers = set(string)<br/>  }))</pre> | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | `"westeurope"` | no |
| <a name="input_public_access_enabled"></a> [public\_access\_enabled](#input\_public\_access\_enabled) | Allow public network access to the platform services. Meant for dev only. | `bool` | `false` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription that receives the resources. | `string` | n/a | yes |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Microsoft Entra tenant. | `string` | n/a | yes |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | Address range of the virtual network. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_databricks_workspace_url"></a> [databricks\_workspace\_url](#output\_databricks\_workspace\_url) | URL of the Databricks workspace. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | URI of the key vault. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Resource group of the platform. |
<!-- END_TF_DOCS -->

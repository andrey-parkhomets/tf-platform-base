# data-factory

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| azurerm | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| azurerm | 4.81.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_data_factory.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory) | resource |
| [azurerm_data_factory_linked_service_data_lake_storage_gen2.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_linked_service_data_lake_storage_gen2) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| linked\_storage\_accounts | Data lake accounts to link, by a short key. The value is the account's DFS endpoint. | `map(string)` | `{}` | no |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics\_workspace\_id | Workspace that receives the factory's diagnostic logs. | `string` | n/a | yes |
| name | Data factory name. | `string` | n/a | yes |
| public\_network\_enabled | Allow access to the factory from the public internet. | `bool` | `true` | no |
| resource\_group\_name | Resource group that holds the factory. | `string` | n/a | yes |
| tags | Tags for all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| id | ID of the data factory. |
| principal\_id | Object ID of the factory's managed identity. |
<!-- END_TF_DOCS -->

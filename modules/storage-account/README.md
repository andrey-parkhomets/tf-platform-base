# storage-account

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
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_account_network_rules.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account_network_rules) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| allowed\_subnet\_ids | Subnets that may reach the account. Everything else is denied. | `list(string)` | `[]` | no |
| containers | Names of the blob containers to create. | `set(string)` | `[]` | no |
| is\_data\_lake | Turn on the hierarchical namespace for a data lake. | `bool` | `false` | no |
| location | Azure region. | `string` | n/a | yes |
| name | Storage account name. Lowercase letters and digits only, 3 to 24 characters. | `string` | n/a | yes |
| replication\_type | Replication type, for example LRS or GRS. | `string` | `"LRS"` | no |
| resource\_group\_name | Resource group that holds the account. | `string` | n/a | yes |
| tags | Tags for all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| id | ID of the storage account. |
| name | Name of the storage account. |
| primary\_dfs\_endpoint | Data lake endpoint of the account. |
<!-- END_TF_DOCS -->

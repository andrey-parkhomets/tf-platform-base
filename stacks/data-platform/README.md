# data-platform

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.9.0 |
| azurerm | ~> 4.0 |
| external | ~> 2.3 |

## Providers

| Name | Version |
|------|---------|
| azurerm | 4.81.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| data\_factory | ../../modules/data-factory | n/a |
| data\_lake | ../../modules/storage-account | n/a |
| databricks | ../../modules/databricks-workspace | n/a |
| function\_app | ../../modules/function-app | n/a |
| key\_vault | ../../modules/key-vault | n/a |
| key\_vault\_endpoint | ../../modules/private-endpoint | n/a |
| lake\_endpoint | ../../modules/private-endpoint | n/a |
| log\_analytics | ../../modules/log-analytics-workspace | n/a |
| network | ../../modules/network | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| data\_lakes | Data lake storage accounts by short key, with their containers. | <pre>map(object({<br/>    containers = set(string)<br/>  }))</pre> | n/a | yes |
| environment | Environment name. | `string` | n/a | yes |
| location | Azure region. | `string` | `"westeurope"` | no |
| public\_access\_enabled | Allow public network access to the platform services. Meant for dev only. | `bool` | `false` | no |
| subscription\_id | Azure subscription that receives the resources. | `string` | n/a | yes |
| tenant\_id | Microsoft Entra tenant. | `string` | n/a | yes |
| vnet\_address\_space | Address range of the virtual network. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| databricks\_workspace\_url | URL of the Databricks workspace. |
| key\_vault\_uri | URI of the key vault. |
| resource\_group\_name | Resource group of the platform. |
<!-- END_TF_DOCS -->

# key-vault

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
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_role_assignment.secret_reader](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.secrets_user](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/role_definition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allowed\_subnet\_ids | Subnets that may reach the vault. Everything else is denied. | `list(string)` | `[]` | no |
| location | Azure region. | `string` | n/a | yes |
| name | Key vault name, 3 to 24 characters. | `string` | n/a | yes |
| resource\_group\_name | Resource group that holds the vault. | `string` | n/a | yes |
| secret\_readers | Object IDs of identities that may read secrets, by a short key. | `map(string)` | `{}` | no |
| tags | Tags for all resources. | `map(string)` | `{}` | no |
| tenant\_id | Microsoft Entra tenant that owns the vault. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the key vault. |
| vault\_uri | URI of the key vault. |
<!-- END_TF_DOCS -->

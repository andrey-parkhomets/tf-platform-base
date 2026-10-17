# private-endpoint

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
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| location | Azure region. | `string` | n/a | yes |
| name | Name suffix of the endpoint. | `string` | n/a | yes |
| private\_dns\_zone\_id | Private DNS zone that resolves the endpoint. Leave empty for none. | `string` | `null` | no |
| resource\_group\_name | Resource group that holds the endpoint. | `string` | n/a | yes |
| subnet\_id | Subnet that gets the endpoint's network interface. | `string` | n/a | yes |
| subresource\_name | Sub-resource of the target, for example blob, dfs, vault or dataFactory. | `string` | n/a | yes |
| tags | Tags for all resources. | `map(string)` | `{}` | no |
| target\_resource\_id | Resource the endpoint connects to. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the private endpoint. |
| private\_ip\_address | Private IP address of the endpoint. |
<!-- END_TF_DOCS -->

# network

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
| [azurerm_network_security_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| address\_space | Address ranges of the virtual network, in CIDR notation. | `list(string)` | n/a | yes |
| location | Azure region. | `string` | n/a | yes |
| name | Name suffix used for the network resources. | `string` | n/a | yes |
| resource\_group\_name | Resource group that holds the network. | `string` | n/a | yes |
| subnets | Subnets by key. Each subnet gets its own network security group. | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    service_endpoints = optional(list(string), [])<br/>  }))</pre> | n/a | yes |
| tags | Tags for all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| subnet\_ids | Subnet IDs by subnet key. |
| vnet\_id | ID of the virtual network. |
<!-- END_TF_DOCS -->

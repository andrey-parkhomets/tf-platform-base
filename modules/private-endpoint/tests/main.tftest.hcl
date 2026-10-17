mock_provider "azurerm" {}

variables {
  name                = "tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/s"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/st"
  subresource_name    = "blob"
}

# DELIBERATELY WRONG (test of the fix round): the resource is called "this", not "nope"
run "endpoint_name" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.nope.name == "pe-tp-test"
    error_message = "The endpoint name must be built from the name input."
  }
}

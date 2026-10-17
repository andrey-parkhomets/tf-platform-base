mock_provider "azurerm" {}

variables {
  name                = "tp-legacy"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/s"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/st"
  subresource_name    = "dfs"
}

run "connection_is_approved_by_hand" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == true
    error_message = "The connection must be a manual one."
  }
}

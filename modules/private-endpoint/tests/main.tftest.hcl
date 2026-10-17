mock_provider "azurerm" {}

variables {
  name                = "sttest"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest"
  subresource_name    = "blob"
}

run "endpoint_names_and_connection_come_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-sttest"
    error_message = "The endpoint name must be the pe- prefix followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-sttest"
    error_message = "The service connection name must be the psc- prefix followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest"
    error_message = "The connection must point at the target_resource_id input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.resource_group_name == "rg-test" && azurerm_private_endpoint.this.location == "westeurope"
    error_message = "The endpoint must be created in the resource group and location given as inputs."
  }

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
    error_message = "The endpoint must take its network interface from the subnet_id input."
  }
}

run "connection_is_automatic_not_manual" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be approved automatically, not left pending for manual approval."
  }
}

run "subresource_name_reaches_the_connection" {
  command = plan

  variables {
    subresource_name = "dfs"
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dfs") && length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1
    error_message = "The connection must list exactly the subresource_name input."
  }
}

run "camel_case_subresource_is_accepted" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dataFactory")
    error_message = "A camel-case sub-resource such as dataFactory must pass validation and reach the connection."
  }
}

run "rejects_subresource_with_hyphen" {
  command = plan

  variables {
    subresource_name = "blob-storage"
  }

  expect_failures = [var.subresource_name]
}

run "rejects_subresource_starting_with_digit" {
  command = plan

  variables {
    subresource_name = "1blob"
  }

  expect_failures = [var.subresource_name]
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group may be created when private_dns_zone_id is left empty."
  }
}

run "dns_zone_group_is_created_for_a_zone" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one DNS zone group must be created when private_dns_zone_id is set."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net")
    error_message = "The DNS zone group must reference the private_dns_zone_id input."
  }
}

run "tags_reach_the_endpoint" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["env"] == "test"
    error_message = "Tags must be set on the private endpoint."
  }
}

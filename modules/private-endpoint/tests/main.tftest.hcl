mock_provider "azurerm" {}

variables {
  name                = "test-endpoint"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttptest001"
  subresource_name    = "blob"
}

run "names_come_from_the_name_input" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-test-endpoint"
    error_message = "The endpoint name must be the pe- prefix followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-test-endpoint"
    error_message = "The private service connection name must be the psc- prefix followed by the name input."
  }
}

run "connects_the_target_as_an_automatic_connection" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttptest001"
    error_message = "The connection must point at the target_resource_id input."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "blob")
    error_message = "The connection must request the subresource_name input (blob)."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be automatic, not manual, so no approval step is needed."
  }
}

run "uses_the_subnet_location_and_resource_group_inputs" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
    error_message = "The endpoint must be placed in the subnet_id input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.location == "westeurope"
    error_message = "The endpoint location must be the location input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.resource_group_name == "rg-test"
    error_message = "The endpoint must be created in the resource_group_name input."
  }
}

run "data_factory_subresource_is_accepted" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dataFactory")
    error_message = "The documented sub-resource dataFactory must reach the connection unchanged."
  }
}

run "tags_are_set_on_the_endpoint" {
  command = plan

  variables {
    tags = {
      env   = "dev"
      owner = "platform"
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["env"] == "dev"
    error_message = "The env tag from the tags input must be set on the endpoint."
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["owner"] == "platform"
    error_message = "The owner tag from the tags input must be set on the endpoint."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No private DNS zone group may be created when private_dns_zone_id is not set."
  }
}

run "dns_zone_group_uses_the_given_zone" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one private DNS zone group must be created when private_dns_zone_id is set."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net")
    error_message = "The DNS zone group must reference the private_dns_zone_id input."
  }
}

run "rejects_subresource_name_with_hyphen" {
  command = plan

  variables {
    subresource_name = "blob-2"
  }

  expect_failures = [var.subresource_name]
}

run "rejects_subresource_name_starting_with_digit" {
  command = plan

  variables {
    subresource_name = "1blob"
  }

  expect_failures = [var.subresource_name]
}

run "rejects_empty_subresource_name" {
  command = plan

  variables {
    subresource_name = ""
  }

  expect_failures = [var.subresource_name]
}

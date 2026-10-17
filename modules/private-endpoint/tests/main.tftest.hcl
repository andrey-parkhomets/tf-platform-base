mock_provider "azurerm" {}

variables {
  name                = "tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/s"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/st"
  subresource_name    = "blob"
}

run "endpoint_name_is_built_from_name" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-tp-test"
    error_message = "The endpoint name must be built from the name input as pe-<name>."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-tp-test"
    error_message = "The private service connection name must be built from the name input as psc-<name>."
  }
}

run "connects_to_target_and_subresource" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/st"
    error_message = "The endpoint must connect to the target_resource_id input."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "blob")
    error_message = "The endpoint must request exactly the subresource_name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be auto-approved (is_manual_connection = false) for the target."
  }
}

run "subresource_name_is_honoured" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dataFactory")
    error_message = "The endpoint must request the subresource_name input, here dataFactory."
  }
}

run "no_dns_zone_group_without_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No private DNS zone group may be created when private_dns_zone_id is null."
  }
}

run "dns_zone_group_when_zone_given" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one private DNS zone group must be created when private_dns_zone_id is set."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net")
    error_message = "The DNS zone group must reference the private_dns_zone_id input."
  }
}

run "tags_are_passed_to_endpoint" {
  command = plan

  variables {
    tags = {
      Environment = "test"
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["Environment"] == "test"
    error_message = "The endpoint must carry the tags input."
  }
}

run "rejects_subresource_name_with_hyphen" {
  command = plan

  variables {
    subresource_name = "data-factory"
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

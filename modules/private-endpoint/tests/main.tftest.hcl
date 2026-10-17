mock_provider "azurerm" {}

variables {
  name                = "ep-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
  subresource_name    = "blob"
  tags = {
    env = "test"
  }
}

run "connects_target_and_subresource" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
    error_message = "The private service connection must point at the target resource."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "blob")
    error_message = "The private service connection must request the blob sub-resource."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1
    error_message = "Exactly one sub-resource must be requested per endpoint."
  }
}

run "names_and_placement_come_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-ep-test"
    error_message = "The endpoint name must be the pe- prefix followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-ep-test"
    error_message = "The connection name must be the psc- prefix followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.resource_group_name == "rg-test"
    error_message = "The endpoint must be created in the resource group given by the input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.location == "westeurope"
    error_message = "The endpoint must be created in the location given by the input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/endpoints"
    error_message = "The endpoint must take its network interface from the subnet given by the input."
  }
}

run "connection_is_auto_approved" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be auto-approved, not manual."
  }
}

run "no_dns_zone_group_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group may be created when private_dns_zone_id is not set."
  }
}

run "dns_zone_group_when_zone_given" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one DNS zone group must be created when private_dns_zone_id is set."
  }

  assert {
    condition     = contains(one(azurerm_private_endpoint.this.private_dns_zone_group).private_dns_zone_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net")
    error_message = "The DNS zone group must reference the private_dns_zone_id input."
  }
}

run "tags_are_set_on_endpoint" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.tags["env"] == "test"
    error_message = "The endpoint must carry the tags given in the input."
  }
}

run "accepts_camel_case_subresource" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dataFactory")
    error_message = "A camel-case sub-resource such as dataFactory must be passed through unchanged."
  }
}

run "rejects_subresource_with_hyphen" {
  command = plan

  variables {
    subresource_name = "blob-1"
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

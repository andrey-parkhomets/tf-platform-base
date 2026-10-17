mock_provider "azurerm" {}

variables {
  name                = "dl-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stdltest"
  subresource_name    = "dfs"
}

run "endpoint_names_are_built_from_the_name_input" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-dl-test"
    error_message = "The endpoint name must be pe-<name>."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-dl-test"
    error_message = "The service connection name must be psc-<name>."
  }
}

run "endpoint_is_wired_to_the_target_and_subnet" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stdltest"
    error_message = "The service connection must point at target_resource_id."
  }

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
    error_message = "The endpoint must sit in subnet_id."
  }

  assert {
    condition     = azurerm_private_endpoint.this.resource_group_name == "rg-test" && azurerm_private_endpoint.this.location == "westeurope"
    error_message = "The endpoint must be created in resource_group_name and location."
  }
}

run "connection_targets_the_requested_subresource_and_is_automatic" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1 && azurerm_private_endpoint.this.private_service_connection[0].subresource_names[0] == "dfs"
    error_message = "The connection must request exactly the subresource_name input (dfs here)."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be auto-approved, not manual."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group may be created when private_dns_zone_id is null."
  }
}

run "dns_zone_group_is_created_when_a_zone_is_given" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one DNS zone group must be created when private_dns_zone_id is set."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids) == 1 && contains(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net")
    error_message = "The DNS zone group must hold exactly the private_dns_zone_id input."
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

run "subresource_name_accepts_camel_case" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names[0] == "dataFactory"
    error_message = "A camelCase subresource such as dataFactory must be accepted and passed through unchanged."
  }
}

run "rejects_subresource_with_a_hyphen" {
  command = plan

  variables {
    subresource_name = "data-lake"
  }

  expect_failures = [var.subresource_name]
}

run "rejects_subresource_starting_with_a_digit" {
  command = plan

  variables {
    subresource_name = "1blob"
  }

  expect_failures = [var.subresource_name]
}

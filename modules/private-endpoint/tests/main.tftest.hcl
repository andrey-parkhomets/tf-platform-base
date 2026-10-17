mock_provider "azurerm" {}

variables {
  name                = "dl-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stdltest"
  subresource_name    = "dfs"
}

run "endpoint_name_and_connection_name_follow_the_input" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-dl-test"
    error_message = "The endpoint name must be pe- followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-dl-test"
    error_message = "The private service connection name must be psc- followed by the name input."
  }
}

run "connection_targets_the_resource_and_subresource" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/stdltest"
    error_message = "The connection must point at target_resource_id."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1 && contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dfs")
    error_message = "The connection must request exactly the subresource_name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be auto-approved, not manual."
  }
}

run "endpoint_lands_in_the_given_subnet_resource_group_and_region" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
    error_message = "The endpoint must be placed in the subnet_id input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.resource_group_name == "rg-test"
    error_message = "The endpoint must be created in resource_group_name."
  }

  assert {
    condition     = azurerm_private_endpoint.this.location == "westeurope"
    error_message = "The endpoint must be created in the location input."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No private DNS zone group may be created when private_dns_zone_id is null."
  }
}

run "dns_zone_group_is_created_when_a_zone_is_given" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one private DNS zone group must be created when a zone is given."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].name == "default"
    error_message = "The DNS zone group must be named default."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids) == 1 && contains(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids, "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.dfs.core.windows.net")
    error_message = "The DNS zone group must contain exactly the private_dns_zone_id input."
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

run "accepts_subresource_names_used_by_the_stacks" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1 && contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dataFactory")
    error_message = "A camel-case subresource such as dataFactory must be passed through unchanged."
  }
}

run "rejects_subresource_name_starting_with_a_digit" {
  command = plan

  variables {
    subresource_name = "1blob"
  }

  expect_failures = [var.subresource_name]
}

run "rejects_subresource_name_with_a_hyphen" {
  command = plan

  variables {
    subresource_name = "blob-storage"
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

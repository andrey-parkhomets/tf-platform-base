mock_provider "azurerm" {}

variables {
  name                = "test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttptest001"
  subresource_name    = "blob"
}

run "names_follow_the_name_input" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-test"
    error_message = "The endpoint name must be pe-<name>."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-test"
    error_message = "The service connection name must be psc-<name>."
  }
}

run "connects_to_the_target_and_subresource" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttptest001"
    error_message = "The connection must point at the target_resource_id input."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1
    error_message = "The connection must request exactly one subresource."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names[0] == "blob"
    error_message = "The subresource_names list must contain the subresource_name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be auto-approved, not manual."
  }
}

run "subresource_name_is_honoured" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names[0] == "dataFactory"
    error_message = "A camel-case subresource such as dataFactory must reach subresource_names unchanged."
  }
}

run "accepts_a_letter_led_alphanumeric_subresource" {
  command = plan

  variables {
    subresource_name = "vault"
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names[0] == "vault"
    error_message = "A plain alphanumeric subresource such as vault must be accepted."
  }
}

run "rejects_subresource_with_hyphen" {
  command = plan

  variables {
    subresource_name = "blob-secondary"
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

run "rejects_empty_subresource" {
  command = plan

  variables {
    subresource_name = ""
  }

  expect_failures = [var.subresource_name]
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No private DNS zone group may be created when private_dns_zone_id is null."
  }
}

run "dns_zone_is_attached_when_given" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one private DNS zone group must be created when private_dns_zone_id is set."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids[0] == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
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

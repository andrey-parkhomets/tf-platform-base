mock_provider "azurerm" {}

variables {
  name                = "tp-dev-blob"
  resource_group_name = "rg-test"
  location            = "westeurope"
  subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/endpoints"
  target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest"
  subresource_name    = "blob"
  tags = {
    environment = "dev"
    managed_by  = "terraform"
  }
}

run "names_endpoint_and_connection_from_name" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-tp-dev-blob"
    error_message = "The endpoint name must be the pe- prefix followed by the name input."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-tp-dev-blob"
    error_message = "The service connection name must be the psc- prefix followed by the name input."
  }
}

run "connects_to_target_resource_and_subresource" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == var.target_resource_id
    error_message = "The endpoint must connect to target_resource_id."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 1 && contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "blob")
    error_message = "The endpoint must connect to exactly the subresource given in subresource_name."
  }
}

run "connection_is_auto_approved" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be auto-approved (is_manual_connection = false); this module does not create manual requests."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No private DNS zone group must be created when private_dns_zone_id is not set."
  }
}

run "adds_dns_zone_group_when_zone_is_given" {
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

run "sets_tags_from_input" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.tags == var.tags
    error_message = "The endpoint must carry the tags input unchanged."
  }
}

run "accepts_camel_case_subresource" {
  command = plan

  variables {
    subresource_name = "dataFactory"
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "dataFactory")
    error_message = "A camel-case sub-resource such as dataFactory must be accepted and passed through."
  }
}

run "rejects_subresource_starting_with_digit" {
  command = plan

  variables {
    subresource_name = "9blob"
  }

  expect_failures = [
    var.subresource_name,
  ]
}

run "rejects_subresource_with_hyphen" {
  command = plan

  variables {
    subresource_name = "blob-store"
  }

  expect_failures = [
    var.subresource_name,
  ]
}

run "rejects_empty_subresource" {
  command = plan

  variables {
    subresource_name = ""
  }

  expect_failures = [
    var.subresource_name,
  ]
}

mock_provider "azurerm" {}

variables {
  name                = "dbw-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "name_is_used_for_the_workspace" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-test"
    error_message = "The workspace name must be the name input."
  }
}

run "managed_resource_group_name_is_derived_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-test-managed"
    error_message = "The managed resource group must be named <resource_group_name>-<name>-managed."
  }
}

run "no_public_ip_is_always_set" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "The workspace must be deployed without public IPs on its cluster nodes."
  }
}

run "sku_defaults_to_premium" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "The sku must default to premium when no sku is given."
  }
}

run "standard_sku_is_honoured" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The sku input standard must reach the workspace."
  }
}

run "unknown_sku_is_rejected" {
  command = plan

  variables {
    sku = "basic"
  }

  expect_failures = [var.sku]
}

run "public_network_access_can_be_disabled" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled = false must reach the workspace."
  }
}

run "tags_reach_the_workspace" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_databricks_workspace.this.tags["env"] == "test"
    error_message = "Tags must be set on the workspace."
  }
}

run "name_at_minimum_length_is_accepted" {
  command = plan

  variables {
    name = "dbw"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw"
    error_message = "A 3 character name must be accepted and used as given."
  }
}

run "name_at_maximum_length_is_accepted" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz0123"
  }

  assert {
    condition     = length(azurerm_databricks_workspace.this.name) == 30
    error_message = "A 30 character name must be accepted and used as given."
  }
}

run "name_shorter_than_three_characters_is_rejected" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "name_longer_than_thirty_characters_is_rejected" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz01234"
  }

  expect_failures = [var.name]
}

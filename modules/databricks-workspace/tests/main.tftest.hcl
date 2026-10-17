mock_provider "azurerm" {}

variables {
  name                = "dbw-tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "managed_resource_group_is_derived_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-tp-test-managed"
    error_message = "The managed resource group must be named after the resource group and the workspace name."
  }
}

run "workspace_name_and_location_are_passed_through" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-tp-test"
    error_message = "The workspace name must be the name input."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.location == "westeurope"
    error_message = "The workspace must be created in the location input."
  }
}

run "no_public_ip_is_always_set" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "Cluster nodes must not get public IP addresses."
  }
}

run "public_access_can_be_turned_off" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "The public_network_access_enabled input must reach the workspace when set to false."
  }
}

run "sku_is_passed_through" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The sku input must be used as the workspace tier."
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

run "name_of_three_characters_is_accepted" {
  command = plan

  variables {
    name = "abc"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "abc"
    error_message = "A three character name is the shortest allowed and must be accepted."
  }
}

run "rejects_name_shorter_than_three_characters" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "rejects_name_longer_than_thirty_characters" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz12345"
  }

  expect_failures = [var.name]
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku = "basic"
  }

  expect_failures = [var.sku]
}

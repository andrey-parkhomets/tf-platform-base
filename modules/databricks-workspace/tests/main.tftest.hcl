mock_provider "azurerm" {}

variables {
  name                = "dbw-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "workspace_has_no_public_ip" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "The workspace must be deployed without public IP addresses on its clusters."
  }
}

run "managed_resource_group_is_derived_from_name" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-test-managed"
    error_message = "The managed resource group must be named <resource group>-<name>-managed."
  }
}

run "name_at_minimum_length_is_accepted" {
  command = plan

  variables {
    name = "abc"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "abc"
    error_message = "A 3 character name must be accepted and used as the workspace name."
  }
}

run "name_at_maximum_length_is_accepted" {
  command = plan

  variables {
    name = "dbw-abcdefghijklmnopqrstuvwxyz"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-abcdefghijklmnopqrstuvwxyz"
    error_message = "A 30 character name must be accepted and used as the workspace name."
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
    name = "dbw-abcdefghijklmnopqrstuvwxyz1"
  }

  expect_failures = [var.name]
}

run "sku_standard_is_honoured" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The workspace sku must follow the sku input when standard is requested."
  }
}

run "rejects_unknown_sku" {
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
    error_message = "Public network access must follow the input when it is set to false."
  }
}

run "tags_are_passed_to_the_workspace" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_databricks_workspace.this.tags["env"] == "test"
    error_message = "Every tag given to the module must be set on the workspace."
  }
}

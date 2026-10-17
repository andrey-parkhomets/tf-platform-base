mock_provider "azurerm" {}

variables {
  name                = "dbw-test-001"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "inputs_reach_the_workspace" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-test-001"
    error_message = "The name input must be used as the workspace name."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.resource_group_name == "rg-test"
    error_message = "The workspace must be created in the resource group given as input."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.location == "westeurope"
    error_message = "The workspace must be created in the location given as input."
  }
}

run "workspace_has_no_public_ip" {
  command = plan
  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "The workspace must always be created with no_public_ip = true."
  }
}

run "managed_resource_group_name_follows_the_pattern" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-test-001-managed"
    error_message = "The managed resource group must be named <resource group>-<name>-managed."
  }
}

run "sku_defaults_to_premium" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "The sku must default to premium when not set."
  }
}

run "standard_sku_is_honoured" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The sku input must be used when set to standard."
  }
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku = "basic"
  }

  expect_failures = [var.sku]
}

run "public_access_input_is_honoured" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled = false must reach the workspace."
  }
}

run "accepts_name_of_three_characters" {
  command = plan

  variables {
    name = "dbw"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw"
    error_message = "A three character name is within the allowed range and must be accepted."
  }
}

run "accepts_name_of_thirty_characters" {
  command = plan

  variables {
    name = "dbw-abcdefghijklmnopqrstuvwxyz"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-abcdefghijklmnopqrstuvwxyz"
    error_message = "A thirty character name is within the allowed range and must be accepted."
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

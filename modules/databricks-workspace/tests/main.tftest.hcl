mock_provider "azurerm" {}

variables {
  name                = "dbw-test-001"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "name_is_passed_to_the_workspace" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-test-001"
    error_message = "The workspace must use the name input."
  }
}

run "name_accepts_three_characters" {
  command = plan

  variables {
    name = "dbw"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw"
    error_message = "A 3 character name must be accepted and used as given."
  }
}

run "name_accepts_thirty_characters" {
  command = plan

  variables {
    name = "dbw-abcdefghijklmnopqrstuvwxyz"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-abcdefghijklmnopqrstuvwxyz"
    error_message = "A 30 character name must be accepted and used as given."
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

run "managed_resource_group_name_is_derived_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-test-001-managed"
    error_message = "The managed resource group must be named <resource group>-<workspace name>-managed."
  }
}

run "sku_defaults_to_premium" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "The workspace sku must default to premium."
  }
}

run "sku_standard_is_honoured" {
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

run "public_network_access_is_honoured_when_disabled" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled = false must reach the workspace."
  }
}

run "workspace_has_no_public_ip" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "Cluster nodes must be deployed without public IP addresses."
  }
}

run "location_and_resource_group_reach_the_workspace" {
  command = plan

  variables {
    location            = "northeurope"
    resource_group_name = "rg-other"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.location == "northeurope"
    error_message = "The location input must be used for the workspace."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.resource_group_name == "rg-other"
    error_message = "The resource_group_name input must be used for the workspace."
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

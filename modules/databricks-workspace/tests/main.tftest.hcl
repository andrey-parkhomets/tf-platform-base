mock_provider "azurerm" {}

variables {
  name                = "dbw-test-001"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "name_and_location_reach_the_workspace" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.name == "dbw-test-001"
    error_message = "The name input must be used as the workspace name."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.location == "westeurope"
    error_message = "The location input must be used as the workspace location."
  }

  assert {
    condition     = azurerm_databricks_workspace.this.resource_group_name == "rg-test"
    error_message = "The resource_group_name input must be used as the workspace resource group."
  }
}

run "managed_resource_group_name_is_derived_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "rg-test-dbw-test-001-managed"
    error_message = "The managed resource group must be named <resource_group_name>-<name>-managed."
  }
}

run "premium_sku_is_the_default" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "The workspace must use the premium sku when sku is not set."
  }
}

run "standard_sku_is_accepted" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The sku input must be honoured when it is standard."
  }
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku = "basic"
  }

  expect_failures = [var.sku]
}

run "accepts_name_at_minimum_length" {
  command = plan

  variables {
    name = "abc"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "abc"
    error_message = "A 3 character name must be accepted and used as the workspace name."
  }
}

run "accepts_name_at_maximum_length" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz1234"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.name == "abcdefghijklmnopqrstuvwxyz1234"
    error_message = "A 30 character name must be accepted and used as the workspace name."
  }
}

run "rejects_name_below_minimum_length" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "rejects_name_above_maximum_length" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxyz12345"
  }

  expect_failures = [var.name]
}

run "public_network_access_can_be_turned_off" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "Setting public_network_access_enabled to false must reach the workspace."
  }
}

run "public_network_access_can_be_turned_on" {
  command = plan

  variables {
    public_network_access_enabled = true
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == true
    error_message = "Setting public_network_access_enabled to true must reach the workspace."
  }
}

run "workspace_never_gets_a_public_ip" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "The workspace must be created with no_public_ip set to true."
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

run "outputs_expose_the_workspace_id_and_url" {
  command = plan

  override_resource {
    target          = azurerm_databricks_workspace.this
    override_during = plan
    values = {
      id            = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Databricks/workspaces/dbw-test-001"
      workspace_url = "adb-1234567890123456.7.azuredatabricks.net"
    }
  }

  assert {
    condition     = output.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Databricks/workspaces/dbw-test-001"
    error_message = "The id output must be the workspace resource id."
  }

  assert {
    condition     = output.workspace_url == "adb-1234567890123456.7.azuredatabricks.net"
    error_message = "The workspace_url output must be the workspace URL."
  }
}

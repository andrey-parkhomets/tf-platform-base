mock_provider "azurerm" {}

variables {
  name                = "log-test-001"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "workspace_uses_pergb2018_and_the_given_inputs" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "The workspace must use the PerGB2018 SKU."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-test-001"
    error_message = "The workspace name must be the name input."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.resource_group_name == "rg-test"
    error_message = "The workspace must be created in the resource_group_name input."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.location == "westeurope"
    error_message = "The workspace must be created in the location input."
  }
}

run "retention_defaults_to_30_days" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Logs must be kept for 30 days when retention_in_days is not set."
  }
}

run "retention_accepts_the_lower_bound" {
  command = plan

  variables {
    retention_in_days = 30
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "30 days must be accepted as the minimum retention."
  }
}

run "retention_input_reaches_the_workspace" {
  command = plan

  variables {
    retention_in_days = 90
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90
    error_message = "The retention_in_days input must be used for the workspace."
  }
}

run "retention_accepts_the_upper_bound" {
  command = plan

  variables {
    retention_in_days = 730
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 730
    error_message = "730 days must be accepted as the maximum retention."
  }
}

run "rejects_retention_below_30_days" {
  command = plan

  variables {
    retention_in_days = 29
  }

  expect_failures = [var.retention_in_days]
}

run "rejects_retention_above_730_days" {
  command = plan

  variables {
    retention_in_days = 731
  }

  expect_failures = [var.retention_in_days]
}

run "tags_reach_the_workspace" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["env"] == "test"
    error_message = "Tags must be set on the Log Analytics workspace."
  }
}

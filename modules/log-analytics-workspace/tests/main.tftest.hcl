mock_provider "azurerm" {}

variables {
  name                = "log-test-001"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "workspace_uses_pay_as_you_go_sku" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "The workspace SKU must be PerGB2018."
  }
}

run "retention_defaults_to_30_days" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Retention must default to 30 days when no value is given."
  }
}

run "retention_input_is_honoured" {
  command = plan

  variables {
    retention_in_days = 90
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90
    error_message = "The retention_in_days input (90) must be set on the workspace."
  }
}

run "name_group_and_location_come_from_inputs" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-test-001"
    error_message = "The workspace name must equal the name input."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.resource_group_name == "rg-test"
    error_message = "The workspace must be created in the resource_group_name input."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.location == "westeurope"
    error_message = "The workspace location must equal the location input."
  }
}

run "tags_are_passed_through" {
  command = plan

  variables {
    tags = {
      env   = "dev"
      owner = "platform"
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["env"] == "dev"
    error_message = "The env tag must be set on the workspace from the tags input."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["owner"] == "platform"
    error_message = "The owner tag must be set on the workspace from the tags input."
  }
}

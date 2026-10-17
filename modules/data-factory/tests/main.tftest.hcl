mock_provider "azurerm" {}

variables {
  name                       = "adf-test-001"
  resource_group_name        = "rg-test"
  location                   = "westeurope"
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
}

run "factory_uses_a_system_assigned_identity" {
  command = plan

  assert {
    condition     = azurerm_data_factory.this.identity[0].type == "SystemAssigned"
    error_message = "The factory must use a system-assigned managed identity."
  }
}

run "no_linked_services_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_data_factory_linked_service_data_lake_storage_gen2.this) == 0
    error_message = "No linked service may be created unless the caller asks for one."
  }
}

run "one_linked_service_per_key_using_managed_identity" {
  command = plan

  variables {
    linked_storage_accounts = {
      raw     = "https://straw001.dfs.core.windows.net"
      curated = "https://stcur001.dfs.core.windows.net"
    }
  }

  assert {
    condition     = length(azurerm_data_factory_linked_service_data_lake_storage_gen2.this) == 2
    error_message = "Expected one linked service for each map key."
  }

  assert {
    condition     = azurerm_data_factory_linked_service_data_lake_storage_gen2.this["raw"].name == "ls-raw" && azurerm_data_factory_linked_service_data_lake_storage_gen2.this["raw"].url == "https://straw001.dfs.core.windows.net"
    error_message = "A linked service must be named ls-<key> and point at the given DFS endpoint."
  }

  assert {
    condition     = alltrue([for ls in azurerm_data_factory_linked_service_data_lake_storage_gen2.this : ls.use_managed_identity == true])
    error_message = "Linked services must authenticate with the managed identity, not account keys."
  }
}

run "diagnostics_go_to_the_given_workspace" {
  command = plan

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this.name == "diag-adf-test-001" && azurerm_monitor_diagnostic_setting.this.log_analytics_workspace_id == var.log_analytics_workspace_id
    error_message = "Diagnostics must be sent to the workspace given in the input."
  }

  assert {
    condition     = toset([for l in azurerm_monitor_diagnostic_setting.this.enabled_log : l.category]) == toset(["PipelineRuns", "ActivityRuns"])
    error_message = "Pipeline and activity runs must be logged."
  }
}

run "public_network_access_follows_the_input" {
  command = plan

  variables {
    public_network_enabled = false
  }

  assert {
    condition     = azurerm_data_factory.this.public_network_enabled == false
    error_message = "Disabling public network access must reach the factory."
  }
}

run "tags_reach_the_factory" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_data_factory.this.tags["env"] == "test"
    error_message = "Tags must be set on the data factory."
  }
}

mock_provider "azurerm" {}

variables {
  name                = "sttptest001"
  resource_group_name = "rg-test"
  location            = "westeurope"
  containers          = ["raw", "curated"]
}

run "account_is_locked_down_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "The account must require TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Public blob access must be off."
  }

  assert {
    condition     = azurerm_storage_account_network_rules.this.default_action == "Deny"
    error_message = "Network access must be denied by default."
  }
}

run "creates_one_container_per_name" {
  command = plan

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Expected one container for each name."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid-Name"
  }

  expect_failures = [var.name]
}

run "account_requires_https_and_disables_shared_keys" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "The account must accept HTTPS traffic only."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared access keys must be disabled, access goes through Entra ID."
  }
}

run "containers_are_private" {
  command = plan

  assert {
    condition     = alltrue([for c in azurerm_storage_container.this : c.container_access_type == "private"])
    error_message = "Every container must be private."
  }
}

run "no_containers_by_default" {
  command = plan

  variables {
    containers = []
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 0
    error_message = "No container may be created when none is requested."
  }
}

run "data_lake_flag_enables_hierarchical_namespace" {
  command = plan

  variables {
    is_data_lake = true
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled == true
    error_message = "is_data_lake must turn on the hierarchical namespace."
  }
}

run "hierarchical_namespace_is_off_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled == false
    error_message = "The hierarchical namespace must be off unless requested."
  }
}

run "replication_type_reaches_the_account" {
  command = plan

  variables {
    replication_type = "GRS"
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "GRS"
    error_message = "The replication_type input must be used."
  }
}

run "allowed_subnets_reach_the_network_rules" {
  command = plan

  variables {
    allowed_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-a"]
  }

  assert {
    condition     = length(azurerm_storage_account_network_rules.this.virtual_network_subnet_ids) == 1
    error_message = "The allowed subnet must be listed in the network rules."
  }

  assert {
    condition     = azurerm_storage_account_network_rules.this.default_action == "Deny"
    error_message = "Allowing a subnet must not change the default action from Deny."
  }
}

run "blob_delete_retention_is_seven_days" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Deleted blobs must be retained for 7 days."
  }
}

run "tags_reach_the_account" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_storage_account.this.tags["env"] == "test"
    error_message = "Tags must be set on the storage account."
  }
}

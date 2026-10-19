mock_provider "azurerm" {}

# The external data source runs scripts/build-info.sh. Mocking it keeps the test deterministic
# and makes sure the script is never executed by the test.
mock_provider "external" {
  mock_data "external" {
    defaults = {
      result = {
        revision = "abc1234"
      }
    }
  }
}

variables {
  name                 = "func-test-001"
  resource_group_name  = "rg-test"
  location             = "westeurope"
  storage_account_name = "sttest001"
  storage_account_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest001"
}

run "app_requires_https_and_modern_tls" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.https_only == true
    error_message = "The function app must accept HTTPS only."
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].minimum_tls_version == "1.2"
    error_message = "The function app must require TLS 1.2."
  }
}

run "app_uses_managed_identity_for_runtime_storage" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.storage_uses_managed_identity == true
    error_message = "The runtime storage must be accessed with the managed identity, not a key."
  }

  assert {
    condition     = azurerm_linux_function_app.this.identity[0].type == "SystemAssigned"
    error_message = "The app needs a system-assigned identity."
  }

  assert {
    condition     = azurerm_role_assignment.runtime_storage.role_definition_name == "Storage Blob Data Owner" && azurerm_role_assignment.runtime_storage.scope == var.storage_account_id
    error_message = "The identity must get Storage Blob Data Owner on the given storage account only."
  }
}

run "names_derive_from_the_name_input" {
  command = plan

  assert {
    condition     = azurerm_service_plan.this.name == "asp-func-test-001"
    error_message = "The service plan name must be asp-<name>."
  }

  assert {
    condition     = azurerm_linux_function_app.this.name == "func-test-001"
    error_message = "The function app name must equal the name input."
  }
}

run "python_version_defaults_and_overrides" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].application_stack[0].python_version == "3.12"
    error_message = "Python 3.12 is the default runtime."
  }
}

run "python_version_can_be_overridden" {
  command = plan

  variables {
    python_version = "3.11"
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].application_stack[0].python_version == "3.11"
    error_message = "The python_version input must reach the runtime stack."
  }
}

run "public_access_follows_the_input" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_linux_function_app.this.public_network_access_enabled == false
    error_message = "Disabling public access must reach the app."
  }
}

run "app_settings_are_merged_with_the_build_revision" {
  command = plan

  variables {
    app_settings = {
      FEATURE_FLAG = "on"
    }
  }

  assert {
    condition     = azurerm_linux_function_app.this.app_settings["FEATURE_FLAG"] == "on"
    error_message = "Caller app settings must be kept."
  }

  assert {
    condition     = azurerm_linux_function_app.this.app_settings["BUILD_REVISION"] == "abc1234"
    error_message = "BUILD_REVISION must come from the build info data source."
  }
}

run "build_revision_cannot_be_set_by_the_caller" {
  command = plan

  variables {
    app_settings = {
      BUILD_REVISION = "caller-value"
    }
  }

  assert {
    condition     = azurerm_linux_function_app.this.app_settings["BUILD_REVISION"] == "abc1234"
    error_message = "The module's BUILD_REVISION must win over a caller-supplied value."
  }
}

run "tags_reach_app_and_plan" {
  command = plan

  variables {
    tags = {
      env = "test"
    }
  }

  assert {
    condition     = azurerm_linux_function_app.this.tags["env"] == "test" && azurerm_service_plan.this.tags["env"] == "test"
    error_message = "Tags must be set on the app and on the service plan."
  }
}

run "service_plan_is_linux_ep2" {
  command = plan

  assert {
    condition     = azurerm_service_plan.this.sku_name == "EP2"
    error_message = "The service plan SKU must be EP2 (Elastic Premium), as set in main.tf."
  }

  assert {
    condition     = azurerm_service_plan.this.os_type == "Linux"
    error_message = "The service plan must be a Linux plan, because the app is a Linux function app."
  }
}

mock_provider "azurerm" {}

variables {
  name                = "kv-tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  secret_readers = {
    adf = "11111111-1111-1111-1111-111111111111"
  }
}

run "vault_uses_rbac_and_purge_protection" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled == true
    error_message = "The vault must use role-based access, not access policies."
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true
    error_message = "Purge protection must be on."
  }
}

run "creates_one_role_assignment_per_reader" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.secret_reader) == 1
    error_message = "Expected one role assignment for each secret reader."
  }
}

run "accepts_the_all_zero_placeholder_tenant_id" {
  command = plan

  variables {
    tenant_id = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = azurerm_key_vault.this.tenant_id == "00000000-0000-0000-0000-000000000000"
    error_message = "The all-zero placeholder GUID must pass tenant_id validation."
  }
}

run "rejects_a_tenant_id_that_is_not_a_guid" {
  command = plan

  variables {
    tenant_id = "contoso.onmicrosoft.com"
  }

  expect_failures = [
    var.tenant_id,
  ]
}
